#
#       (c) Copyright Four Js 2017. 
#
#                                 Apache License
#                           Version 2.0, January 2004
#
#       https://www.apache.org/licenses/LICENSE-2.0

#+ Genero 4GL wrapper around the Calendar plugin
#+ at https://github.com/FourjsGenero-Cordova-Plugins/Calendar-PhoneGap-Plugin
OPTIONS SHORT CIRCUIT
IMPORT util
IMPORT os
CONSTANT CALENDAR="Calendar"
CONSTANT _CALL="call"
CONSTANT CORDOVA="cordova"
CONSTANT CALLWOW="callWithoutWaiting"
PUBLIC TYPE TIME_AS_NUMBER DECIMAL
PUBLIC TYPE CALENDAR_DATE DATETIME YEAR TO SECOND

PUBLIC TYPE eventOptionsT RECORD
   title STRING,
   location STRING,
   notes STRING,
   startDate CALENDAR_DATE,
   endDate CALENDAR_DATE,
   options RECORD
     allday BOOLEAN,
     firstReminderMinutes INT,
     secondReminderMinutes INT,
     recurrence STRING, --daily,weekly,monthly,yearly
     recurrenceInterval INT,
     recurrenceEndDate CALENDAR_DATE,
     calendarName STRING,
     calendarId STRING,
     url STRING,
     spanFutureEvents BOOLEAN --used for modify
   END RECORD
END RECORD

PUBLIC TYPE calendarT RECORD
  id STRING,
  name STRING,
  type STRING
END RECORD

PUBLIC TYPE findOptionsT RECORD
  title STRING,
  location STRING,
  notes STRING,
  startDate CALENDAR_DATE,
  endDate CALENDAR_DATE,
  id STRING,
  calendarName STRING
END RECORD

PUBLIC DEFINE eventOptions eventOptionsT

PUBLIC TYPE eventType RECORD --return type for find function
    title STRING,
    calendar STRING,
    id STRING,
    startDate CALENDAR_DATE, 
    endDate CALENDAR_DATE,
    lastModified CALENDAR_DATE,
    firstReminderMinutes FLOAT,
    secondReminderMinutes FLOAT,
    location STRING,
    url STRING,
    notes STRING,
    allday BOOLEAN,
    attendees DYNAMIC ARRAY OF RECORD
        name STRING,
        URL STRING,
        status STRING,
        type STRING,
        role STRING
    END RECORD,
    rrule RECORD 
        freq STRING, --for ex "weekly" or "monthly"
        interval INT, --every <interval> week , every <interval> month etc
        wkst STRING, --weekstart
        byday STRING, --for ex SU,MO,TU,WE,TH,FR,SA
        bymonthday STRING, --for ex 2,15
        until CALENDAR_DATE, --recurring stops at this date if set
        count INT --if set then it means recurring stops after <count> occurences
     END RECORD
END RECORD

TYPE eventTypeInternal RECORD --return type for find function
    title STRING,
    calendar STRING,
    id STRING,
    startDate CALENDAR_DATE, 
    endDate CALENDAR_DATE,
    lastModified CALENDAR_DATE,
    firstReminderMinutes FLOAT,
    secondReminderMinutes FLOAT,
    location STRING,
    url STRING,
    notes STRING,
    allday BOOLEAN,
    attendees DYNAMIC ARRAY OF RECORD
        name STRING,
        URL STRING,
        status STRING,
        type STRING,
        role STRING
    END RECORD,
    rrule RECORD --IOS 
        freq STRING, 
        interval INT,
        until RECORD
           date CALENDAR_DATE,
           count INT
        END RECORD
    END RECORD,
    recurrence RECORD --Android 
        freq STRING, --for ex WEEKLY or MONTHLY
        interval INT,
        wkst STRING, --weekstart
        byday STRING, --for ex SU,MO,TU,WE,TH,FR,SA
        bymonthday STRING, --for ex 2,15
        until CALENDAR_DATE,
        count INT
     END RECORD
END RECORD

--private types and variables
--The plugin requires in several places startTime and endTime as
--milliseconds since 1970, we expose those as startDate and endDate to the 4GL side
--furthermore the iOS plugin is very picky about getting NULL values
--as explicit null JSON literals ,otherwise crashes may occur

--helper macro to save a lot of boilerplate conversion between
--different record types
&define ASSIGN_RECORD(src,dest) CALL util.JSON.parse(util.JSON.stringify(src),dest)

DEFINE optionsInt RECORD 
   title STRING,
   location STRING,
   notes STRING,
   startTime TIME_AS_NUMBER ATTRIBUTE(json_null="null"),
   endTime TIME_AS_NUMBER ATTRIBUTE(json_null="null"),
   options RECORD
     firstReminderMinutes INT ATTRIBUTE(json_null="null"),
     secondReminderMinutes INT ATTRIBUTE(json_null="null"),
     recurrence STRING ATTRIBUTE(json_null="null"), --daily,weekly,monthly,yearly
     recurrenceInterval INT,
     recurrenceEndTime TIME_AS_NUMBER,
     calendarName STRING ATTRIBUTE(json_null="null"),
     calendarId STRING,
     url STRING ATTRIBUTE(json_null="null")
   END RECORD
END RECORD

PRIVATE TYPE calendarOptionsT RECORD
    calendarName STRING ATTRIBUTE(json_null="null"),
    calendarColor STRING ATTRIBUTE(json_null="null") 
END RECORD

PRIVATE TYPE deleteOptionsT RECORD
   title STRING ATTRIBUTE(json_null="null"),
   location STRING ATTRIBUTE(json_null="null"),
   notes STRING ATTRIBUTE(json_null="null"),
   startTime TIME_AS_NUMBER ATTRIBUTE(json_null="null"),
   endTime TIME_AS_NUMBER ATTRIBUTE(json_null="null"),
   id STRING ATTRIBUTE(json_null="null"),
   calendarName STRING ATTRIBUTE(json_null="null"),
   spanFutureEvents BOOLEAN ATTRIBUTE(json_null="null")
END RECORD

DEFINE m_error STRING --holds the error message from the last operation

MAIN
  LET eventOptions.title="hallo"
  LET eventOptions.startDate=CURRENT
  CALL outer2Int(eventOptions.*)
  DISPLAY "calTitle:",optionsInt.title
  DISPLAY "calDate:",optionsInt.startTime
END MAIN

#+ inits the plugin
#+ must be called prior other calls
PUBLIC FUNCTION init()
  DEFINE doc om.DomDocument
  DEFINE root,n,p om.DomNode
  DEFINE nlm,nld om.NodeList
#+ GMI:if the plugin initialization is done in the very first instructions
#+ of the mobile program the delaying mechanism for the splash screen
#+ may block the whole startup (because the plugin initialization blocks the main thread), 
#+ so we create a temporary Menu to let the IOS event loop kick in 
  IF ui.Interface.getFrontEndName()=="GMI" OR ui.Interface.getFrontEndName()=="GMA" THEN
    LET doc=ui.Interface.getDocument()
    LET root=doc.getDocumentElement()
    LET nlm=root.selectByTagName("Menu")
    LET nld=root.selectByTagName("Dialog")
    IF nlm.getLength()==0 AND
       nld.getLength()==0 THEN 
       MENU "Wait for Confirmation"
         BEFORE MENU
           LET nlm=root.selectByTagName("MenuAction")
           IF nlm.getLength()==1 THEN --remove our help action
             LET n=nlm.item(1)
             LET p=n.getParent()
             CALL p.removeChild(n)
           END IF
           CALL ui.Interface.refresh()
           EXIT MENU
       END MENU
    END IF
    CALL ui.Interface.refresh()
  END IF
END FUNCTION

PRIVATE FUNCTION err_frontcall()
  DEFINE msg STRING
  DEFINE idx,endidx INT

  LET msg=err_get(status)
  IF status=-6333 THEN --cut off the leading bla
    LET msg=msg.subString(msg.getIndexOf("Reason:",1)+7,msg.getLength())
  END IF
  IF (idx:=msg.getIndexOf("NSLocalizedDescription = ",1))<>0 THEN
    --extract from the silly IOS format
    LET idx=idx+26
    LET endidx=msg.getIndexOf("\n",idx)
    IF endidx<>0 THEN
      LET msg=msg.subString(idx,endidx-3)
    END IF
  END IF
  LET m_error=msg
  DISPLAY "ERROR:",m_error
END FUNCTION

PRIVATE FUNCTION getCalendarOptions()
  DEFINE opts calendarOptionsT
  INITIALIZE opts.* TO NULL
  RETURN opts.*
END FUNCTION

#+ Converts a 4GL date into the milliseconds since 1970 
#+ (this is what a new Date.getTime() returns in JS)
#+ @param d the Date to convert
#+ @return the milliseconds since 01/01/1970
PUBLIC FUNCTION dateTime2MilliSinceEpoch(d CALENDAR_DATE)
  IF d IS NULL THEN
    RETURN NULL
  END IF
  RETURN util.Datetime.toSecondsSinceEpoch(d)*1000
END FUNCTION

&define DATETIME2JS(opJS,op4GL) \
  LET opJS.startTime=dateTime2MilliSinceEpoch(op4GL.startDate)  \
  LET opJS.endTime=dateTime2MilliSinceEpoch(op4GL.endDate) 

PRIVATE FUNCTION outer2Int(opts eventOptionsT)
   DEFINE d0,d1 DATE
   INITIALIZE optionsInt.* TO NULL
   LET optionsInt.title=opts.title
   LET optionsInt.location=opts.location
   LET optionsInt.notes=opts.notes
   IF opts.options.allday THEN
     LET d0=opts.startDate
     LET d1=opts.endDate
     IF d1==d0 THEN --same date: we need to add 24h
       LET d1=d0 + 1
     END IF
     LET opts.startDate=d0
     LET opts.endDate=d1
   END IF
   DATETIME2JS(optionsInt,opts)
   LET optionsInt.options.firstReminderMinutes=opts.options.firstReminderMinutes
   LET optionsInt.options.secondReminderMinutes=opts.options.secondReminderMinutes
   LET optionsInt.options.recurrence=opts.options.recurrence
   LET optionsInt.options.recurrenceInterval=opts.options.recurrenceInterval
   LET optionsInt.options.recurrenceEndTime=dateTime2MilliSinceEpoch(opts.options.recurrenceEndDate)
   LET optionsInt.options.calendarName=opts.options.calendarName
   LET optionsInt.options.calendarId=opts.options.calendarId
   LET optionsInt.options.url=opts.options.url
END FUNCTION

#+ Creates a new Event
#+ @param options see eventOptionsT
#+ @return an event id on success, NULL in the error case
#+ use getLastError() to retrieve the error message
#+ on IOS the event id can be used to modify or delete the event
#+ on Android the event id can not be used for further operations
PUBLIC FUNCTION createEventWithOptions(options eventOptionsT) RETURNS STRING
    DEFINE result STRING
    CALL outer2Int(options.*) 
    TRY
      CALL ui.interface.frontcall(CORDOVA,_CALL,
        [CALENDAR,"createEventWithOptions",optionsInt],[result])
    CATCH
      CALL err_frontcall()
    END TRY
    RETURN result
END FUNCTION

#+ Creates a new Event interactively with a native UI dialog
#+ @param options see eventOptionsT
#+ @return an event id on success, NULL in the error case
#+ use getLastError() to retrieve the error message
#+ on IOS the event id can be used to modify or delete the event
#+ on Android the event id can not be used for further operations
PUBLIC FUNCTION createEventInteractively(options eventOptionsT) RETURNS STRING
    DEFINE result STRING
    CALL outer2Int(options.*) 
    TRY
      CALL ui.interface.frontcall(CORDOVA,_CALL,
        [CALENDAR,"createEventInteractively",optionsInt],[result])
    CATCH
      CALL err_frontcall()
    END TRY
    RETURN result
END FUNCTION

{
#+ Return all events for a given calendar.
#+ Convenient for quickly looking whats inside a calendar
#+ IOS only , on Android the call fails, therefore for production use only findEventsWithOptions().
#+ @param calendarName must not be NULL
#+ @return all events and an error string in case the operation failed
PUBLIC FUNCTION findAllEventsInNamedCalendar(calendarName STRING) 
           --RETURNS DYNAMIC ARRAY OF eventType ,STRING
  DEFINE arr DYNAMIC ARRAY OF eventType
  DEFINE options calendarOptionsT
  DEFINE err STRING
  CALL getCalendarOptions() RETURNING options.*
  LET options.calendarName=calendarName
  TRY
    CALL ui.interface.frontcall(CORDOVA,_CALL,
            [CALENDAR,"findAllEventsInNamedCalendar",options],[arr])
  CATCH
    CALL err_frontcall()
    LET err=m_error
  END TRY
  RETURN arr ,err
END FUNCTION
}

#+ Creates a new Calendar
#+ (Android: no clue how the createEvent/findEvent/deleteEvent functions can act on this calendar )
#+ @param calendarName name for the newly created calendar
#+ @param color a webbish rgb value a la '#ff0000' is required, or NULL
#+ @return NULL on error, an id for the created calendar
FUNCTION createCalendar(calendarName STRING,color STRING) RETURNS STRING
  DEFINE result STRING
  DEFINE options calendarOptionsT
  LET options.calendarName=calendarName
  LET options.calendarColor=color
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                       [CALENDAR,"createCalendar",options],[result])
    IF result IS NULL THEN
      LET result="id0"
    END IF
  CATCH
    CALL err_frontcall()
  END TRY
  RETURN result
END FUNCTION

#+ this function is implemented only on IOS and allows to modify an existing event
#+ @param findOptions if the find options contain a valid event id 
#+ (returned by createEventWithOptions) the changes act on that event
#+ using NULL for the id uses the title,location etc to find the event
#+ @param changeOptions contains the values to be override the old values in the event 
#+ @return the event Identifier if a change took place, NULL otherwise
#+ in the error case the error can be retrieved with getLastError()
FUNCTION modifyEventWithOptions(findOptions findOptionsT,changeOptions eventOptionsT)
  DEFINE result STRING
  DEFINE internal RECORD
    title STRING ATTRIBUTE(json_null="null"),
    location STRING ATTRIBUTE(json_null="null"),
    notes STRING ATTRIBUTE(json_null="null"),
    startTime TIME_AS_NUMBER ,
    endTime TIME_AS_NUMBER ,
    newTitle STRING ,
    newLocation STRING,
    newNotes STRING ,
    newStartTime TIME_AS_NUMBER ,
    newEndTime TIME_AS_NUMBER ,
    options RECORD
      id STRING ATTRIBUTE(json_null="null"),
      calendarName STRING ATTRIBUTE(json_null="null")
    END RECORD,
    newOptions RECORD
      allday BOOLEAN,
      calendarName STRING ATTRIBUTE(json_null="null"),
      firstReminderMinutes INT ATTRIBUTE(json_null="null"),
      secondReminderMinutes INT ATTRIBUTE(json_null="null"),
      recurrence STRING ATTRIBUTE(json_null="null"), --daily,weekly,monthly,yearly
      recurrenceInterval INT,
      recurrenceEndTime TIME_AS_NUMBER,
      url STRING ATTRIBUTE(json_null="null"),
      spanFutureEvents BOOLEAN ATTRIBUTE(json_null="null")
    END RECORD
  END RECORD
  ASSIGN_RECORD(findOptions,internal)
  LET internal.options.id=findOptions.id
  LET internal.options.calendarName=findOptions.calendarName
  DATETIME2JS(internal,findOptions)
  LET internal.newTitle=changeOptions.title
  LET internal.newLocation=changeOptions.location
  LET internal.newNotes=changeOptions.notes
  LET internal.newStartTime=dateTime2MilliSinceEpoch(changeOptions.startDate)
  LET internal.newEndTime=dateTime2MilliSinceEpoch(changeOptions.endDate)
  LET internal.newOptions.allday=changeOptions.options.allday
  LET internal.newOptions.calendarName=dateTime2MilliSinceEpoch(changeOptions.options.calendarName)
  LET internal.newOptions.firstReminderMinutes=changeOptions.options.firstReminderMinutes
  LET internal.newOptions.secondReminderMinutes=changeOptions.options.secondReminderMinutes
  LET internal.newOptions.recurrence=changeOptions.options.recurrence
  LET internal.newOptions.recurrenceInterval=changeOptions.options.recurrenceInterval
  LET internal.newOptions.recurrenceEndTime=dateTime2MilliSinceEpoch(changeOptions.options.recurrenceEndDate)
  LET internal.newOptions.url=changeOptions.options.url
  LET internal.newOptions.spanFutureEvents=changeOptions.options.spanFutureEvents
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"modifyEventWithOptions",internal],[result])
    RETURN result
  END TRY
  CALL err_frontcall()
  RETURN NULL
END FUNCTION

{
FUNCTION modifyEventInteractivelyWithFindOptions(findOptions findOptionsT) RETURNS STRING
  DEFINE result STRING
  DEFINE internal RECORD
    id STRING,
    calendarName STRING,
    title STRING ATTRIBUTE(json_null="null"),
    location STRING ATTRIBUTE(json_null="null"),
    notes STRING ATTRIBUTE(json_null="null"),
    startTime TIME_AS_NUMBER ,
    endTime TIME_AS_NUMBER 
  END RECORD
  LET internal.id=findOptions.id
  LET internal.calendarName=findOptions.calendarName
  LET internal.title=findOptions.title
  LET internal.location=findOptions.location
  LET internal.notes=findOptions.notes
  DATETIME2JS(internal,findOptions)
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"modifyEventInteractively",internal],[result])
    IF result IS NULL THEN
      LET result="Cancel"
    END IF
    RETURN result
  CATCH
    CALL err_frontcall()
    RETURN NULL
  END TRY
END FUNCTION
}

#+ modifies the given event in a native UI dialog
#+ @param event the event to modify
FUNCTION modifyEventInteractively(event eventType) RETURNS STRING
  DEFINE findOpts findOptionsT
  INITIALIZE findOpts.* TO NULL
  ASSIGN_RECORD(event,findOpts)
  LET findOpts.calendarName=event.calendar
  RETURN modifyEventInteractivelyWithFindOptions(findOpts.*)
END FUNCTION

#+ opens the calendar app on the device for a specific date
#+ @param d The date the calendar app should display
FUNCTION openCalendar(d CALENDAR_DATE)
  DEFINE options RECORD
    date TIME_AS_NUMBER
  END RECORD
  LET options.date=dateTime2MilliSinceEpoch(d)
  CALL ui.Interface.frontCall(CORDOVA,CALLWOW,
                             [CALENDAR,"openCalendar",options],[])
END FUNCTION

#+ Returns a list of all calendars
#+ @return a list of calendars + a non NULL error string in the error case
FUNCTION listCalendars() RETURNS DYNAMIC ARRAY OF calendarT,STRING
  DEFINE internal DYNAMIC ARRAY OF RECORD
    id STRING,
    name STRING,
    displayName STRING,
    type STRING
  END RECORD
  DEFINE result DYNAMIC ARRAY OF calendarT
  DEFINE i INT
  DEFINE err STRING
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"listCalendars"],[internal])
    --IOS returns name, Android displayName (for whatever reason...)
    FOR i=1 TO internal.getLength()
      LET result[i].id=internal[i].id
      LET result[i].name=IIF(internal[i].name IS NOT NULL,internal[i].name,
                                                          internal[i].displayName)
      LET result[i].type=internal[i].type
    END FOR
  CATCH
    CALL err_frontcall()
    LET err=m_error
  END TRY
  RETURN result,err
END FUNCTION

{
#+ does nothing on IOS, need to be checked on Android
FUNCTION listEventsInRange()
  DEFINE result STRING
  CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"listEventsInRange"],[result])
END FUNCTION
}

#+ Deletes an event for a specific calendar : IOS only .
#+ The given parameters are used to identify one or more events
#+ so for example events in a given time frame can be deleted.
#+ @param findOptions same as for finding an event
#+ @param spanFutureEvents If set and the event is recurring, all recurring events will be removed too, otherwise only the event with matching startDate etc will be deleted
#+ @param calendarName calendar where the deletion should take place
#+ @return NULL in the error case, an non NULL string in the case the deletion was successful, use getLastError() to get the error reason
FUNCTION deleteEventFromNamedCalendarWithFindOptions(findOptions findOptionsT,spanFutureEvents BOOLEAN,calendarName STRING) RETURNS STRING
  DEFINE internal deleteOptionsT
  DEFINE result STRING
  LET internal.id=findOptions.id
  LET internal.title=findOptions.title
  LET internal.location=findOptions.location
  LET internal.notes=findOptions.notes
  DATETIME2JS(internal,findOptions)
  LET internal.spanFutureEvents=spanFutureEvents
  LET internal.calendarName=calendarName
  TRY
  CALL ui.Interface.frontCall(CORDOVA,_CALL,
       [CALENDAR,
       IIF(calendarName IS NULL,"deleteEvent","deleteEventFromNamedCalendar"),
       internal],[result])
    IF result IS NULL THEN
      LET result="ok"
    END IF
  CATCH
    CALL err_frontcall()
  END TRY
  RETURN result
END FUNCTION

#+ Deletes an event for the active calendar
#+ the given parameters are used to identify one or more events
#+ so for example events in a given time frame can be deleted
#+ @param findOptions same as for finding an event
#+ @param spanFutureEvents If set and the event is recurring, all recurring events will be removed too, otherwise only the event with matching startDate etc will be deleted
#+ @return NULL in the error case, an non NULL string in the case the deletion was successful, use getLastError() to get the error reason
FUNCTION deleteEventWithFindOptions(findOptions findOptionsT,spanFutureEvents BOOLEAN) RETURNS STRING
  RETURN deleteEventFromNamedCalendarWithFindOptions(findOptions.*,spanFutureEvents,NULL)
END FUNCTION

#+ Deletes an event for the active calendar
#+ @param event structure returned by findEvent
#+ @param spanFutureEvents If set and the event is recurring, all recurring events will be removed too, otherwise only the event with matching startDate etc will be deleted
#+ @return NULL in the error case, an non NULL string in the case the deletion was successful, use getLastError() to get the error reason
FUNCTION deleteEvent(event eventType,spanFutureEvents BOOLEAN) RETURNS STRING
  DEFINE findOpts findOptionsT
  INITIALIZE findOpts.* TO NULL
  ASSIGN_RECORD(event,findOpts)
  RETURN deleteEventWithFindOptions(findOpts.*,spanFutureEvents)
END FUNCTION

#+ Deletes an event for a specific calendar : IOS only .
#+ @param event structure returned by findEvent
#+ @param spanFutureEvents If set and the event is recurring, all recurring events will be removed too, otherwise only the event with matching startDate etc will be deleted
#+ @param calendarName calendar where the deletion should take place
#+ @return NULL in the error case, an non NULL string in the case the deletion was successful, use getLastError() to get the error reason
FUNCTION deleteEventFromNamedCalendar(event eventType,spanFutureEvents BOOLEAN,calendarName STRING) RETURNS STRING
  DEFINE findOpts findOptionsT
  INITIALIZE findOpts.* TO NULL
  ASSIGN_RECORD(event,findOpts)
  RETURN deleteEventFromNamedCalendarWithFindOptions(findOpts.*,spanFutureEvents,calendarName)
END FUNCTION

#+ Helper function for findEventsWithOptions
#+ @return an initialized findOptionsT RECORD
FUNCTION getFindOptions() RETURNS findOptionsT
  DEFINE fo findOptionsT
  INITIALIZE fo.* TO NULL
  RETURN fo.*
END FUNCTION

#+ return whether the given event is a recurring event
#+ @param event event returned by findEvents...
#+ @return TRUE is recurring, FALSE if NOT recurring
FUNCTION isRecurring(event eventType)
  RETURN event.rrule.freq IS NOT NULL
END FUNCTION

#+ finds events either via id or by the combination of title...endTime
#+ the calendarName option is only valid under IOS and only effective if 
#+ id is not set
#+ @param options see findOptionsT
#+ @return an array of events (can be empty) + an NOT NULL error string in the error case
#+
#+ @code
#+   DEFINE options fglcdvCalendar.findOptionsT
#+   DEFINE eventArr DYNAMIC ARRAY OF fglcdvCalendar.eventType
#+   LET options=fglcdvCalendar.getFindOptions()
#+   LET options.startTime=CURRENT
#+   LET options.endTime=CURRENT+7
#+   --return the events for 1 week in the default calendar
#+   CALL fglcdvCalendar.findEventWithOptions(options) RETURNING eventArr
#+
FUNCTION findEventsWithOptions(options findOptionsT) RETURNS DYNAMIC ARRAY OF eventType,STRING
  DEFINE arr DYNAMIC ARRAY OF eventTypeInternal
  DEFINE results DYNAMIC ARRAY OF eventType
  DEFINE internal RECORD
    title STRING ATTRIBUTE(json_null="null"),
    location STRING ATTRIBUTE(json_null="null"),
    notes STRING ATTRIBUTE(json_null="null"),
    startTime TIME_AS_NUMBER ,
    endTime TIME_AS_NUMBER ,
    options RECORD
      id STRING ATTRIBUTE(json_null="null"),
      calendarName STRING ATTRIBUTE(json_null="null")
    END RECORD
  END RECORD
  DEFINE ev eventTypeInternal
  DEFINE err STRING
  DEFINE i, len INT
  LET internal.title=options.title
  LET internal.location=options.location
  LET internal.notes=options.notes
  IF options.startDate IS NULL THEN 
    --the plugin produces nonsense for NULL dates..we just include eternity
    LET options.startDate="01/01/1970"
    IF options.endDate IS NULL THEN
      LET options.endDate=CURRENT + 1000 UNITS YEAR
    END IF
  ELSE
    IF options.endDate IS NULL THEN
      LET options.endDate=options.startDate
    END IF
  END IF
  DATETIME2JS(internal,options)
  LET internal.options.id=options.id
  LET internal.options.calendarName=options.calendarName
  TRY --the original call name is misleading, it returns an array of events
  CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"findEventWithOptions",internal],
                             [arr])
  LET len=arr.getLength()
  FOR i=1 TO len
    LET ev.*=arr[i].*
    LET results[i].title=ev.title
    LET results[i].calendar=ev.calendar
    LET results[i].id=ev.id
    LET results[i].startDate=ev.startDate
    LET results[i].endDate=ev.endDate
    LET results[i].lastModified=ev.lastModified
    LET results[i].firstReminderMinutes=ev.firstReminderMinutes
    LET results[i].secondReminderMinutes=ev.secondReminderMinutes
    LET results[i].location=ev.location
    LET results[i].url=ev.url
    LET results[i].notes=ev.notes
    LET results[i].allday=ev.allday
    ASSIGN_RECORD(ev.attendees,results[i].attendees) 
    CASE 
    WHEN ev.rrule.freq IS NOT NULL AND ui.Interface.getFrontEndName()=="GMI"
      LET results[i].rrule.freq=ev.rrule.freq
      LET results[i].rrule.interval=ev.rrule.interval
      LET results[i].rrule.until=ev.rrule.until.date
      IF ev.rrule.until.count>0 THEN
        LET results[i].rrule.count=ev.rrule.until.count
      END IF
      --wkst,byday,bymonthday are not set on IOS
    WHEN ev.recurrence.freq IS NOT NULL AND ui.Interface.getFrontEndName()=="GMA"
      LET results[i].rrule.freq=DOWNSHIFT(ev.recurrence.freq)
      LET results[i].rrule.wkst=ev.recurrence.wkst
      LET results[i].rrule.byday=ev.recurrence.byday
      LET results[i].rrule.bymonthday=ev.recurrence.bymonthday
      --no clue if interval and until are actually set on Android
      LET results[i].rrule.interval=ev.recurrence.interval
      LET results[i].rrule.until=ev.recurrence.until
    END CASE
  END FOR
  CATCH
    CALL err_frontcall()
    LET err=m_error
  END TRY
  RETURN results,err
END FUNCTION

#+ Deletes the given calendar
#+ @param calendarName must not be NULL
#+ @return NULL on error , an ok string indicating the deletion was performed otherwise
FUNCTION deleteCalendar(calendarName STRING) RETURNS STRING
  DEFINE result STRING
  DEFINE options calendarOptionsT
  LET options.calendarName=calendarName
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"deleteCalendar",options],[result])
    IF result IS NULL THEN
      LET result="ok"
    END IF
  CATCH
    CALL err_frontcall()
  END TRY
  RETURN result
END FUNCTION


#+ Checks if we are allowed to read from the Calendar
#+ On IOS this includes also the write permission
#+ @return TRUE upon success, FALSE otherwise
FUNCTION hasReadPermission() RETURNS BOOLEAN
  DEFINE result BOOLEAN
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"hasReadPermission"],[result])
    RETURN result
  END TRY
  RETURN FALSE
END FUNCTION


#+ Explicitly show the permission dialog in case we have no permission
#+ On IOS this includes also the write permission
#+ @return TRUE upon success, FALSE otherwise
FUNCTION requestReadPermission() RETURNS BOOLEAN
  DEFINE result BOOLEAN
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"requestReadPermission"],[result])
    RETURN result
  END TRY
  RETURN FALSE
END FUNCTION

#+ Checks if we are allowed to write information to the Calendar
#+ On IOS this include also the read permission
#+ @return TRUE upon success, FALSE otherwise
FUNCTION hasWritePermission() RETURNS BOOLEAN
  DEFINE result BOOLEAN
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"hasWritePermission"],[result])
    RETURN result
  END TRY
  RETURN FALSE
END FUNCTION

#+ Checks if we are allowed to read/write information from/to the Calendar
#+ @return TRUE upon success, FALSE otherwise
FUNCTION hasReadWritePermission() RETURNS BOOLEAN
  DEFINE result BOOLEAN
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"hasReadWritePermission"],[result])
    RETURN result
  END TRY
  RETURN FALSE
END FUNCTION

#+ Explicitly show the permission dialog in case we have no permission
#+ @return TRUE upon success, FALSE otherwise
FUNCTION requestWritePermission() RETURNS BOOLEAN
  DEFINE result BOOLEAN
  TRY
   CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"requestWritePermission"],[result])
    RETURN result
  END TRY
  RETURN FALSE
END FUNCTION

#+ Explicitly show the permission dialog in case we have no permission
#+ @return TRUE upon success, FALSE otherwise
FUNCTION requestReadWritePermission() RETURNS BOOLEAN
  DEFINE result BOOLEAN
  TRY
    CALL ui.Interface.frontCall(CORDOVA,_CALL,
                             [CALENDAR,"requestReadWritePermission"],[result])
    RETURN result
  END TRY
  RETURN FALSE
END FUNCTION

#+ gives back the last Error message of the previous operation 
#+ @return the error message
FUNCTION getLastError()
  RETURN m_error
END FUNCTION
