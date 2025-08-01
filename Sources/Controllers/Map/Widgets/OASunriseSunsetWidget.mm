//
//  OASunriseSunsetWidget.m
//  OsmAnd Maps
//
//  Created by Dmitry Svetlichny on 09.03.2023.
//  Copyright © 2023 OsmAnd. All rights reserved.
//

#import "OASunriseSunsetWidget.h"
#import "OASunriseSunsetWidgetState.h"
#import "SunriseSunset.h"
#import "OAOsmAndFormatter.h"
#import "Localization.h"
#import "OsmAndApp.h"
#import "OAAppSettings.h"
#import "OAApplicationMode.h"
#import "OsmAnd_Maps-Swift.h"
#import "OAResourcesUIHelper.h"

static const NSTimeInterval updateInterval = 60;
static const double locationChangeAccuracy = 0.0001;

@implementation OASunriseSunsetWidget
{
    OsmAndAppInstance _app;
    OAAppSettings *_settings;
    OASunriseSunsetWidgetState *_state;
    NSArray<NSString *> *_items;
    CLLocationCoordinate2D _cachedCenterLatLon;
    NSTimeInterval _timeToNextUpdate;
    NSTimeInterval _cachedNextTime;
    NSTimeInterval _lastUpdateTime;
    BOOL _isForceUpdate;
    BOOL _isLocationChanged;
}

- (instancetype)initWithState:(OASunriseSunsetWidgetState *)state
                      appMode:(OAApplicationMode *)appMode
                 widgetParams:(NSDictionary *)widgetParams
{
    self = [super init];
    if (self)
    {
        _app = [OsmAndApp instance];
        _settings = [OAAppSettings sharedManager];
        _state = state;
        self.widgetType = [state getWidgetType];
        [self configurePrefsWithId:state.customId appMode:appMode widgetParams:widgetParams];
        
        __weak OASunriseSunsetWidget *selfWeak = self;
        self.updateInfoFunction = ^BOOL{
            [selfWeak updateInfo];
            return NO;
        };
        self.onClickFunction = ^(id sender) {
            [selfWeak onWidgetClicked];
        };
        
        [self setText:@"-" subtext:@""];
        [self setIcon:[_state getWidgetIconName]];
        _isForceUpdate = YES;
    }
    return self;
}

- (BOOL) updateInfo
{
    [self updateCachedLocation];
    if (![self isUpdateNeeded])
        return  NO;
    
    if ([self isShowTimeLeft])
    {
        NSTimeInterval leftTime = [self getTimeLeft];
        NSString *left = [self formatTimeLeft:leftTime];
        _items = [left componentsSeparatedByString:@" "];
    }
    else
    {
        NSTimeInterval nextTime = [self getNextTime];
        NSString *next = [self formatNextTime:nextTime];
        _items = [next componentsSeparatedByString:@" "];
    }
    if (_items.count > 1)
        [self setText:_items.firstObject subtext:_items.lastObject];
    else
        [self setText:_items.firstObject subtext:nil];
    
    [self setContentTitle:[self getWidgetName]];
    
    if (OAWidgetType.sunPosition == self.widgetType)
    {
        [self setIcon:[_state getWidgetIconName]];
    }
    
    _isForceUpdate = NO;
    _isLocationChanged = NO;
    _lastUpdateTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval timeDifference = _cachedNextTime - _lastUpdateTime;
    if (timeDifference > updateInterval)
        _timeToNextUpdate = timeDifference - floor(timeDifference / updateInterval) * updateInterval;
    else
        _timeToNextUpdate = timeDifference;
    
    return YES;
}

- (BOOL)isUpdateNeeded
{
    if (_isForceUpdate || _isLocationChanged)
        return YES;
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if ([self isShowTimeLeft])
        return (_lastUpdateTime + _timeToNextUpdate) <= currentTime;
    else
        return _cachedNextTime <= currentTime;
}

- (void) onWidgetClicked
{
    _isForceUpdate = YES;
    if ([self isShowTimeLeft])
        [[self getPreference] set:EOASunriseSunsetNext];
    else
        [[self getPreference] set:EOASunriseSunsetTimeLeft];
    [self updateInfo];
}

- (BOOL) isShowTimeLeft
{
    return [[self getPreference] get] == EOASunriseSunsetTimeLeft;
}

- (OACommonInteger *) getPreference
{
    return [_state getPreference];
}

- (OAWidgetState *)getWidgetState
{
    return _state;
}

- (OATableDataModel *)getSettingsData:(OAApplicationMode *)appMode
            widgetConfigurationParams:(NSDictionary<NSString *,id> * _Nullable)widgetConfigurationParams
                             isCreate:(BOOL)isCreate
{
    OAWidgetType *type = [_state getWidgetType];
    
    OATableDataModel *data = [[OATableDataModel alloc] init];
    OATableSectionData *section = [data createNewSection];
    section.headerText = OALocalizedString(@"shared_string_settings");
    
    EOASunPositionMode currentValue = type == OAWidgetType.sunPosition
    ? (EOASunPositionMode)[_state getSunPositionPreference].defValue
    : (EOASunPositionMode)[[_state getSunPositionPreference] get:appMode];

    if (type == OAWidgetType.sunPosition)
    {
        OATableRowData *row = section.createNewRow;
        row.cellType = OAValueTableViewCell.getCellIdentifier;
        row.key = @"value_pref";
        row.title = OALocalizedString(@"shared_string_mode");
        row.descr = OALocalizedString(@"shared_string_mode");
        [row setObj:_state.getSunPositionPreference forKey:@"pref"];
        
        if (widgetConfigurationParams)
        {
            NSString *key = [self findKeyWithPrefixInParams:widgetConfigurationParams prefix:@"sun_position_widget_mode"];
            if (key != nil)
            {
                NSNumber *widgetValue = widgetConfigurationParams[key];
                if (widgetValue != nil)
                    currentValue = (EOASunPositionMode)widgetValue.intValue;
            }
        }
        else if (!isCreate)
        {
            currentValue = (EOASunPositionMode)[[_state getSunPositionPreference] get:appMode];
        }
        [row setObj:[self getTitleForSunPositionMode:currentValue] forKey:@"value"];
        [row setObj:self.getPossibleFormatValues forKey:@"possible_values"];
    }
    
    OATableRowData *row = section.createNewRow;
    row.cellType = OAValueTableViewCell.getCellIdentifier;
    row.key = @"value_pref";
    NSString *title = OALocalizedString(type == OAWidgetType.sunPosition ? @"shared_string_format" : @"recording_context_menu_show");

    row.title = title;
    row.descr = title;

    [row setObj:_state.getPreference forKey:@"pref"];
    
    EOASunriseSunsetMode currentSunriseSunsetMode = (EOASunriseSunsetMode)_state.getPreference.defValue;
    
    if (widgetConfigurationParams)
    {
        NSString *key = [self findKeyWithPrefixInParams:widgetConfigurationParams prefix:[_state getPrefId]];
        if (key != nil)
        {
            NSNumber *widgetValue = widgetConfigurationParams[key];
            if (widgetValue != nil)
                currentSunriseSunsetMode = (EOASunriseSunsetMode)widgetValue.intValue;
        }
    }
    else if (!isCreate)
    {
        currentSunriseSunsetMode = (EOASunriseSunsetMode)[_state.getPreference get:appMode];
    }
    
    [row setObj:[self getTitle:currentSunriseSunsetMode sunPositionMode:currentValue] forKey:@"value"];
    [row setObj:[self getPossibleValuesWithSunPositionMode:currentValue] forKey:@"possible_values"];
   
    return data;
}

- (NSString *)findKeyWithPrefixInParams:(NSDictionary *)widgetConfigurationParams prefix:(NSString *)prefix
{
    for (NSString *paramKey in widgetConfigurationParams)
    {
        if ([paramKey hasPrefix:prefix])
        {
            return paramKey;
        }
    }
    return nil;
}

- (NSArray<OATableRowData *> *)getPossibleFormatValues
{
    NSMutableArray<OATableRowData *> *res = [NSMutableArray array];
    
    NSDictionary *dict = @{
        @(EOASunPositionModeSunPositionMode):OALocalizedString(@"shared_string_next_event"),
        @(EOASunPositionModeSunsetMode):OALocalizedString(@"map_widget_sunset"),
        @(EOASunPositionModeSunriseMode):OALocalizedString(@"map_widget_sunrise")
    };
    
    for (NSNumber *key in dict)
    {
        OATableRowData *row = [[OATableRowData alloc] init];
        row.cellType = OASimpleTableViewCell.getCellIdentifier;
        [row setObj:key forKey:@"value"];
        row.title = dict[key];
        [res addObject:row];
    }
    
    return res;
}

- (NSArray<OATableRowData *> *) getPossibleValuesWithSunPositionMode:(EOASunPositionMode)sunPositionMode
{
    NSMutableArray<OATableRowData *> *res = [NSMutableArray array];
    
    OATableRowData *row = [[OATableRowData alloc] init];
    row.cellType = OASimpleTableViewCell.getCellIdentifier;
    [row setObj:@(EOASunriseSunsetTimeLeft) forKey:@"value"];
    row.title = [self getTitle:EOASunriseSunsetTimeLeft sunPositionMode:sunPositionMode];
    row.descr = [self getDescription:EOASunriseSunsetTimeLeft];
    [res addObject:row];

    row = [[OATableRowData alloc] init];
    row.cellType = OASimpleTableViewCell.getCellIdentifier;
    [row setObj:@(EOASunriseSunsetNext) forKey:@"value"];
    row.title = [self getTitle:EOASunriseSunsetNext sunPositionMode:sunPositionMode];
    row.descr = [self getDescription:EOASunriseSunsetNext];
    [res addObject:row];

    return res;
}

- (NSString *)getWidgetName {
    EOASunPositionMode sunPositionMode = (EOASunPositionMode)[[_state getSunPositionPreference] get];
    
    NSString *sunsetStringId = OALocalizedString(@"map_widget_sunset");
    NSString *sunriseStringId = OALocalizedString(@"map_widget_sunrise");
    NSMutableString *result = [NSMutableString string];
    
    if (OAWidgetType.sunset == self.widgetType || (OAWidgetType.sunPosition == self.widgetType && sunPositionMode == EOASunPositionModeSunsetMode)) {
        [result appendString:sunsetStringId];
    } else if (OAWidgetType.sunPosition == self.widgetType && sunPositionMode == EOASunPositionModeSunPositionMode) {
        [result appendString:_state.lastIsDayTime ? sunsetStringId : sunriseStringId];
    } else {
        [result appendString:sunriseStringId];
    }
    
    EOASunriseSunsetMode sunriseSunsetMode = (EOASunriseSunsetMode)[[self getPreference] get];
    if (sunriseSunsetMode == EOASunriseSunsetNext)
    {
        [result appendFormat:@", %@", OALocalizedString(@"shared_string_next")];
    }
    else if (sunriseSunsetMode == EOASunriseSunsetTimeLeft)
    {
        [result appendFormat:@", %@", OALocalizedString(@"map_widget_sunrise_sunset_time_left")];
    }
    
    return result;
}

- (NSString *)getTitleForSunPositionMode:(EOASunPositionMode)mode {
    switch (mode)
    {
        case EOASunPositionModeSunPositionMode:
            return OALocalizedString(@"shared_string_next_event");
        case EOASunPositionModeSunsetMode:
            return OALocalizedString(@"map_widget_sunset");
        case EOASunPositionModeSunriseMode:
            return OALocalizedString(@"map_widget_sunrise");
    }
}

- (NSString *)getTitle:(EOASunriseSunsetMode)ssm sunPositionMode:(EOASunPositionMode)sunPositionMode
{
    switch (ssm)
    {
        case EOASunriseSunsetTimeLeft:
            return OALocalizedString(@"map_widget_sunrise_sunset_time_left");
        case EOASunriseSunsetNext:
            return [self getNextEventString:sunPositionMode];
        default:
            return @"";
    }
}

- (NSString *)getNextEventString:(EOASunPositionMode)sunPositionMode {
    OAWidgetType *type = [_state getWidgetType];
    NSString *eventString = @"";
    
    if (OAWidgetType.sunPosition == type)
    {
        switch (sunPositionMode)
        {
            case EOASunPositionModeSunriseMode:
                eventString = @"map_widget_next_sunrise";
                break;
            case EOASunPositionModeSunsetMode:
                eventString = @"map_widget_next_sunset";
                break;
            default:
                eventString = @"shared_string_next_event";
                break;
        }
    }
    else
    {
        eventString = OAWidgetType.sunrise == type ? @"map_widget_next_sunrise" : @"map_widget_next_sunset";
    }

    return OALocalizedString(eventString);
}

- (NSString *)getDescription:(EOASunriseSunsetMode)ssm
{
    switch (ssm)
    {
        case EOASunriseSunsetTimeLeft:
        {
            NSTimeInterval leftTime = [self getTimeLeft];
            return [self formatTimeLeft:leftTime];
        }
        case EOASunriseSunsetNext:
        {
            NSTimeInterval nextTime = [self getNextTime];
            return [self formatNextTime:nextTime];
        }
        default:
            return @"";
    }
}

- (NSTimeInterval)getTimeLeft
{
    NSTimeInterval nextTime = [self getNextTime];
    return nextTime > 0 ? abs(nextTime - NSDate.date.timeIntervalSince1970) : -1;
}

- (NSTimeInterval)getNextTime
{
    NSDate *now = [NSDate date];
    SunriseSunset *sunriseSunset = [self createSunriseSunset:now];
    
    NSDate *sunrise = [sunriseSunset getSunrise];
    NSDate *sunset = [sunriseSunset getSunset];
    NSDate *nextTimeDate;
    EOASunPositionMode sunPositionMode = (EOASunPositionMode)[[_state getSunPositionPreference] get];
    OAWidgetType *type = [_state getWidgetType];
    if (OAWidgetType.sunset == type || (OAWidgetType.sunPosition == type && sunPositionMode == EOASunPositionModeSunsetMode))
    {
        nextTimeDate = sunset;
    }
    else if (OAWidgetType.sunPosition == type && sunPositionMode == EOASunPositionModeSunPositionMode)
    {
        _state.lastIsDayTime = [sunriseSunset isDaytime];
        nextTimeDate = _state.lastIsDayTime ? sunset : sunrise;
    }
    else
    {
        nextTimeDate = sunrise;
    }
    
    if (nextTimeDate)
    {
        if ([nextTimeDate compare:now] == NSOrderedAscending)
        {
            NSDateComponents *dayComponent = [[NSDateComponents alloc] init];
            dayComponent.day = 1;
            
            NSCalendar *theCalendar = [NSCalendar currentCalendar];
            nextTimeDate = [theCalendar dateByAddingComponents:dayComponent toDate:nextTimeDate options:0];
        }
        _cachedNextTime = nextTimeDate.timeIntervalSince1970;
        return _cachedNextTime;
    }
    
    return 0;
}

- (SunriseSunset *) createSunriseSunset:(NSDate *)date
{
    double longitude = _cachedCenterLatLon.longitude;
    SunriseSunset *sunriseSunset = [[SunriseSunset alloc] initWithLatitude:_cachedCenterLatLon.latitude longitude:longitude < 0 ? 360 + longitude : longitude dateInputIn:date tzIn:[NSTimeZone localTimeZone]];
    return sunriseSunset;
}

- (NSString *) formatTimeLeft:(NSTimeInterval)timeLeft
{
    return [self getFormattedTime:timeLeft];
}

- (NSString *)getFormattedTime:(NSTimeInterval)timeInterval
{
    NSString *formattedDuration = [self formatMinutesDuration:timeInterval / 60];
    return [NSString stringWithFormat:OALocalizedString(@"ltr_or_rtl_combine_via_space"), formattedDuration, OALocalizedString(@"int_hour")];;
}

- (NSString *)formatMinutesDuration:(int)minutes
{
    int min = minutes % 60;
    int hours = minutes / 60;
   
    return [NSString stringWithFormat:@"%02d:%02d", hours, min];
}

- (NSString *) formatNextTime:(NSTimeInterval)nextTime
{
    NSDate *nextDate = [NSDate dateWithTimeIntervalSince1970:nextTime];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm EE"];
    return [dateFormatter stringFromDate:nextDate];
}

- (void) updateCachedLocation
{
    CLLocationCoordinate2D newCenterLatLon = [OAResourcesUIHelper getMapLocation];
    if (![self isLocationsEqual:_cachedCenterLatLon with:newCenterLatLon])
    {
        _cachedCenterLatLon = newCenterLatLon;
        _isLocationChanged = YES;
    }
}

- (BOOL) isLocationsEqual:(CLLocationCoordinate2D)firstCoordinate with:(CLLocationCoordinate2D)secondCoordinate
{
    return [OAMapUtils areLatLonEqual:firstCoordinate coordinate2:secondCoordinate precision:locationChangeAccuracy];
}

@end
