//
//  DownloadingCellResourceHelper.swift
//  OsmAnd Maps
//
//  Created by Max Kojin on 11/06/24.
//  Copyright © 2024 OsmAnd. All rights reserved.
//

@objc protocol DownloadingCellResourceHelperDelegate: AnyObject {
    func onDownloadingCellResourceNeedUpdate(_ task: OADownloadTask?)
    func onStopDownload(_ resourceItem: OAResourceSwiftItem)
    @objc optional func onDownloadTaskFinished(resourceId: String)
}

@objcMembers
class DownloadingCellResourceHelper: DownloadingCellBaseHelper {
    
    weak var delegate: DownloadingCellResourceHelperDelegate?
    var hostViewController: UIViewController?
    var stopWithAlertMessage = false
    var showDownloadingBytesInDescription = false
    
    private var resourceItems = [String: OAResourceSwiftItem]()
    private var downloadTaskProgressObserver: OAAutoObserverProxy?
    private var downloadTaskCompletedObserver: OAAutoObserverProxy?
    private var localResourcesChangedObserver: OAAutoObserverProxy?
    
    override init() {
        super.init()
        resourceItems = [String: OAResourceSwiftItem]()
        downloadTaskProgressObserver = OAAutoObserverProxy(self, withHandler: #selector(onDownloadResourceTaskProgressChanged), andObserve: OsmAndApp.swiftInstance().downloadsManager.progressCompletedObservable)
        downloadTaskCompletedObserver = OAAutoObserverProxy(self, withHandler: #selector(onDownloadResourceTaskFinished), andObserve: OsmAndApp.swiftInstance().downloadsManager.completedObservable)
        localResourcesChangedObserver = OAAutoObserverProxy(self, withHandler: #selector(onLocalResourcesChanged), andObserve: OsmAndApp.swiftInstance().localResourcesChangedObservable)
    }
    
    deinit {
        if downloadTaskProgressObserver != nil {
            downloadTaskProgressObserver?.detach()
            downloadTaskProgressObserver = nil
        }
        if downloadTaskCompletedObserver != nil {
            downloadTaskCompletedObserver?.detach()
            downloadTaskCompletedObserver = nil
        }
        if localResourcesChangedObserver != nil {
            localResourcesChangedObserver?.detach()
            localResourcesChangedObserver = nil
        }
    }
    
    // MARK: - Resource methods
    
    override func startDownload(_ resourceId: String) {
        if let resourceItem = getResource(resourceId) {
            if resourceItem.isOutdatedItem() {
                OAResourcesUISwiftHelper.offerDownloadAndUpdate(of: resourceItem, onTaskCreated: { [weak self] task in
                    self?.delegate?.onDownloadingCellResourceNeedUpdate(task)
                }, onTaskResumed: nil)
            } else {
                OAResourcesUISwiftHelper.offerDownloadAndInstall(of: resourceItem, onTaskCreated: { [weak self] task in
                    self?.delegate?.onDownloadingCellResourceNeedUpdate(task)
                }, onTaskResumed: nil)
            }
        }
    }
    
    override func stopDownload(_ resourceId: String) {
        if stopWithAlertMessage {
            if let resourceItem = getResource(resourceId) {
                OAResourcesUISwiftHelper.offerCancelDownload(of: resourceItem, onTaskStop: { [weak self] _ in
                    self?.delegate?.onStopDownload(resourceItem)
                }, completionHandler: { [weak self] alert in
                    DispatchQueue.main.async { [weak self] in
                        if let alert {
                            self?.hostViewController?.present(alert, animated: true)
                        }
                    }
                })
            }
        } else {
            // Stop immediately
            if let task = getDownloadTask(resourceId) {
                task.stop()
            }
        }
    }
    
    override func isInstalled(_ resourceId: String) -> Bool {
        if let resourceItem = getResource(resourceId) {
            return resourceItem.isInstalled() || super.isInstalled(resourceId)
        }
        return false
    }
    
    override func isDownloading(_ resourceId: String) -> Bool {
        if let resourceItem = getResource(resourceId) {
            resourceItem.refreshDownloadTask()
            return resourceItem.downloadTask() != nil
        }
        return false
    }
    
    override func isFinished(_ resourceId: String) -> Bool {
        let isDownloading = isDownloading(resourceId)
        let isInstalled = isInstalled(resourceId)
        let isOutdated = OAResourcesUISwiftHelper.is(inOutdatedResourcesList: resourceId)
        return !isDownloading && isInstalled && !isOutdated
    }
    
    override func helperHasItemFor(_ resourceId: String) -> Bool {
        resourceItems[resourceId] != nil
    }
    
    func getAllResourceIds() -> [String] {
        Array(resourceItems.keys)
    }
    
    func getResource(_ resourceId: String) -> OAResourceSwiftItem? {
        resourceItems[resourceId]
    }
    
    func saveResource(resource: OAResourceSwiftItem, resourceId: String) {
        resourceItems[resourceId] = resource
    }
    
    func isDisabled(_ resourceId: String) -> Bool {
        guard let resourceItem = getResource(resourceId), let iapHelper = OAIAPHelper.sharedInstance() else { return false }
        let type = resourceItem.resourceType()
        if !iapHelper.wiki.isActive() && type == .wikiMapRegion {
            return true
        } else if !iapHelper.srtm.isActive() && (type == .srtmMapRegion || type == .hillshadeRegion || type == .slopeRegion) {
            return true
        }
        return false
    }
    
    private func getDownloadTask(_ resourceId: String) -> OADownloadTask? {
        OsmAndApp.swiftInstance().downloadsManager.downloadTasks(withKey: "resource:" + resourceId).first as? OADownloadTask
    }
    
    // MARK: - Cell setup methods
    
    @discardableResult override func setupCell(_ resourceId: String) -> DownloadingCell? {
        if let resourceItem = getResource(resourceId) {
            resourceItem.refreshDownloadTask()
            var subtitle = ""
            if showDownloadingBytesInDescription {
                subtitle = String(resourceItem.formatedSizePkg())
            } else {
                subtitle = String(format: "%@  •  %@", resourceItem.type(), resourceItem.formatedSizePkg())
            }

            var title = resourceItem.title() ?? ""
            if title.isEmpty {
                title = OAResourcesUISwiftHelper.title(ofResourceType: resourceItem.resourceType(),
                                                       in: resourceItem.worldRegion(),
                                                       withRegionName: true,
                                                       withResourceType: true)
            }
            let isDownloading = isDownloading(resourceId)
            
            // get cell with default settings
            let cell = super.setupCell(resourceId: resourceId, title: title, isTitleBold: false, desc: subtitle, leftIconName: getLeftIconName(resourceId), rightIconName: getRightIconName(resourceId), isDownloading: isDownloading)
            
            if isDisabled(resourceId) {
                cell?.titleLabel.textColor = .textColorSecondary
                cell?.rightIconVisibility(false)
            }
            return cell
        }
        return nil
    }
    
    override func getLeftIconName(_ resourceId: String) -> String? {
        if let resourceItem = getResource(resourceId) {
            return resourceItem.iconName()
        }
        return nil
    }
    
    override func onCellClicked(_ resourceId: String) {
        if !isFinished(resourceId) || isAlwaysClickable {
            if !isDownloading(resourceId) {
                if !isDisabled(resourceId) {
                    startDownload(resourceId)
                } else {
                    showActivatePluginPopup(resourceId)
                }
            } else {
                stopDownload(resourceId)
            }
        }
    }
    
    func configureWith(resourceItem: OAResourceSwiftItem?,
                       cell: DownloadingCell) {
        guard let resourceItem, let resourceId = extractResourceId(from: resourceItem) else { return }
        if getResource(resourceId) == nil {
            saveResource(resource: resourceItem, resourceId: resourceId)
        }
        if resourceItem.downloadTask() != nil {
            saveStatus(resourceId: resourceId, status: .inProgress)
        }
        if statuses[resourceId] == nil {
            statuses[resourceId] = .idle
        }
        if progresses[resourceId] == nil {
            progresses[resourceId] = 0
        }
        
        cells[resourceId] = cell
        setupCell(resourceId)
    }
    
    func getOrCreateCell(_ resourceId: String, swiftResourceItem: OAResourceSwiftItem?) -> DownloadingCell? {
        if let swiftResourceItem, swiftResourceItem.objcResourceItem != nil {
            if getResource(resourceId) == nil {
                saveResource(resource: swiftResourceItem, resourceId: resourceId)
            }
            if swiftResourceItem.downloadTask() != nil {
                saveStatus(resourceId: resourceId, status: .inProgress)
            }
            return super.getOrCreateCell(resourceId)
        }
        return nil
    }
    
    private func showActivatePluginPopup(_ resourceId: String) {
        if let resourceItem = getResource(resourceId) {
            let type = resourceItem.resourceType()
            if type == .wikiMapRegion {
                OAPluginPopupViewController.ask(forPlugin: kInAppId_Addon_Wiki)
            } else if type == .srtmMapRegion || type == .hillshadeRegion || type == .slopeRegion {
                OAPluginPopupViewController.ask(forPlugin: kInAppId_Addon_Srtm)
            }
        }
    }
    
    private func extractResourceId(from item: OAResourceSwiftItem?) -> String? {
        guard let item, item.objcResourceItem != nil else { return nil }
        if let multipleItem = item as? OAMultipleResourceSwiftItem {
            return multipleItem.getResourceId()
        }
        
        return item.resourceId()
    }
    
    // MARK: - Downloading cell progress observer's methods
    
    @objc private func onDownloadResourceTaskProgressChanged(observer: Any, key: Any, value: Any) {
        guard let resourceId = Self.getResourceIdFromNotificationKey(key: key, value: value), let parsedValue = value as? NSNumber else { return }
        let progress = parsedValue.floatValue
        
        DispatchQueue.main.async { [weak self] in
            guard let self, self.helperHasItemFor(resourceId) else { return }
            self.setCellProgress(resourceId: resourceId, progress: progress, status: .inProgress)
        }
    }
    
    override func setCellProgress(resourceId: String, progress: Float, status: ItemStatusType) {
        super.setCellProgress(resourceId: resourceId, progress: progress, status: status)
        if showDownloadingBytesInDescription {
            guard let resourceItem = getResource(resourceId) else { return }
            guard let cell = getOrCreateCell(resourceId) else { return }
            guard let subtitle = OAResourcesUISwiftHelper.formatedDownloadingProgressString(resourceItem.sizePkg(), progress: progress) else { return }
            cell.descriptionLabel.text = subtitle
        }
    }
    
    @objc private func onDownloadResourceTaskFinished(observer: Any, key: Any, value: Any) {
        guard let resourceId = Self.getResourceIdFromNotificationKey(key: key, value: value) else { return }
        var progress: Float = 1
        if let parsedValue = value as? NSNumber {
            progress = parsedValue.floatValue
        } else if let task = key as? OADownloadTask {
            progress = task.progressCompleted
        }
        
        if helperHasItemFor(resourceId) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.setCellProgress(resourceId: resourceId, progress: progress, status: .finished)
                if self.isInstalled(resourceId) {
                    self.delegate?.onDownloadTaskFinished?(resourceId: resourceId)
                }
              
                // Start next downloading if needed
                if let tasks = OsmAndApp.swiftInstance().downloadsManager.keysOfDownloadTasks(), !tasks.isEmpty {
                    if let nextTask = OsmAndApp.swiftInstance().downloadsManager.firstDownloadTasks(withKey: tasks[0] as? String) {
                        nextTask.resume()
                    }
                }
            }
        }
    }
    
    @objc private func onLocalResourcesChanged(observer: Any, key: Any, value: Any) {
        guard let hostViewController else { return }
        DispatchQueue.main.async { [weak self] in
            if !hostViewController.isViewLoaded || hostViewController.view.window == nil {
                return
            }
            OAResourcesUISwiftHelper.onDownldedResourceInstalled()
            self?.delegate?.onDownloadingCellResourceNeedUpdate(nil)
        }
    }
    
    override func refreshDownloadingContent() {
        for resourceId in resourceItems.keys {
            if let task = getDownloadTask(resourceId) {
                
                if task.progressCompleted == 1 && task.state == .finished {
                    DispatchQueue.main.async { [weak self] in
                        self?.setCellProgress(resourceId: resourceId, progress: task.progressCompleted, status: .finished)
                        // Start next downloading if needed
                        if let tasks = OsmAndApp.swiftInstance().downloadsManager.keysOfDownloadTasks(), !tasks.isEmpty {
                            if let nextTask = OsmAndApp.swiftInstance().downloadsManager.firstDownloadTasks(withKey: tasks[0] as? String) {
                                nextTask.resume()
                            }
                        }
                    }
                } else if task.progressCompleted > 0 && task.state == .running {
                    DispatchQueue.main.async { [weak self] in
                        self?.setCellProgress(resourceId: resourceId, progress: task.progressCompleted, status: .inProgress)
                    }
                }
            }
        }
    }
    
    static func getResourceIdFromNotificationKey(key: Any, value: Any) -> String? {
        // When we're creating a cell Contour Lines resource, we don't know which subfile user will download (srtm or srtmf).
        // But we're allready need a "resourceId" key for dictionary at this moment.
        // Anyway, user allowed to download and store only type of Contour Line resource (srtm or srtmf file).
        // So on cell creating we can use any common key for booth of them. Let it be "srtm".
        //
        // "resource:africa.srtmf" -> "africa.srtm"
        
        guard let task = key as? OADownloadTask, var taskKey = task.key else { return nil }
        
        // Skip all downloads that are not resources
        if !taskKey.hasPrefix("resource:") {
            return nil
        }
        
        taskKey = taskKey.replacingOccurrences(of: "resource:", with: "").replacingOccurrences(of: ".srtmf.obf", with: ".srtm.obf")
        return taskKey
    }
}
