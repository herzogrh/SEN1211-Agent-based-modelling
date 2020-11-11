__includes [ "utilities.nls"] ; all the boring but important stuff not related to content
extensions [ csv table profiler]


globals [
  ; variables for the map
  topleftx
  toplefty
  bottomrightx
  bottomrighty

  day ; 1 = Monday, 7 = Sunday
  totaldays ; total runtime in days of the system
  ticksperday ; calculated by the user's resolution input
  tickstoday ; count of the numbers of ticks on one day

  pls-average ; save the pls average once per day for performance reasons
  viability-average ; save the viability average once per day for performance reasons

  number-citizens ; the number of citizens in the model

  ; Increases of Viability and PLS are all relative to a set "little increse". Medium increases are defined as two little increases and large increases as three little increases
  viability-increase-little ; a little viability increase (per hour spent at an initiative)
  pls-increase-little ; a little pls increase
  pls-problem-youth-decrease ; pls descrese when encountering problem youth
  pls-litter-decrease ; pls descrese when encountering litter
  pls-burglary-decrease ; pls descrese when encountering burglaries
  qr-scanning-chance ; the chance that a citizen scans a QR code at a specific location

  number-burglaries ; stores how many burglaries happened
  community-center ; stores the patch of the community center
]


; Breeds  ------------------------------------------------------------------------------
breed [citizens citizen]
breed [community-workers community-worker]
breed [police-officers police-officer]
breed [waste-collectors waste-collector]
breed [problem-youth problem-youngster]


; Agent Variables -----------------------------------------------------------------------

patches-own [
  location ; the string holding the name of this location, default is 0
  category ; string holding the category of the location, default is 0
  viability ; if initiative, 0-100 score, default is 0
  initiative-time ; the duration the initiative has been in place so far in days, default is 0

]

citizens-own [
  pls ; the perceived livelihood and safety index of a citizen
  children ; boolean, whether one has children or not
  job ; boolean, whether one has a job or not
  religious ; boolean, whether one is religious or not
  part-of-initiative ; boolean, whether one is part of an initiative or not
  house ; the home patch of the turtle
  work ; save the working place as an agent variable to not calculate it each round
  initiative ; save the patch of the initiative the agent is taking part in
  school ; patch where children of a citizen go to school
  schedule ; create a daily schedule that each agent adheres to
  qrcodes-scanned ; number of qr codes scanned by the agents
  initiative-threshold ; the amount of qr-codes that a citizen needs to scan before they start an initiative
  speed ; in patches per tick (will be calculated with the resolution chosen)
  interactions ; number of interactions a citizen has had from the start of the model run
]


community-workers-own [
  schedule ; daily schedule with initiatives to visit
  speed ; speed at which they move forward in patches per tick (will be calculated with the resolution chosen)
]

police-officers-own [
  station ; the station patch of a police officer
  speed ; in patches per tick (will be calculated with the resolution chosen)
  schedule ; daily schedule with crimes locations to go to
]

waste-collectors-own [
  start-working-day ; beginning tick of the working day
  end-working-day  ; ending tick of the working day
  speed ; in patches per tick (will be calculated with the resolution chosen)

]

problem-youth-own [
  speed ; in patches per tick (will be calculated with the resolution chosen)
  target-patch ; the location where to go next
]

to execute-profiler
  profiler:reset
  setup ;; set up the model
  profiler:start ;; start profiling
  repeat 60 [ go ] ;; run something you want to measure
  profiler:stop ;; stop profiling
  print profiler:report ;; view the results
end



; Setup -----------------------------------------------------------------------------------------------------------------
to setup
  clear-all

  ; Map setup
  setupMap
  loadData

  ; Setup of turtles and patches
  setup-globals
  setup-citizens
  setup-initiatives
  setup-community-workers
  setup-crimes
  setup-litter
  setup-waste-collectors
  setup-police
  setup-problem-youth [60]

  reset-ticks
end

to setup-globals
  ; Timekeeping setup
  set day 0
  set totaldays 0
  set ticksperday 1440 / resolution
  set tickstoday 0

  ; Number of agents
  set number-citizens 210 ; scaled down 100x due to performance reasons

  ; Global variable settings
  set viability-increase-little (0.08 / 60) * resolution
  set pls-increase-little 0.00001 * resolution ; pls increase is dependent on the resolution chosen
  set pls-problem-youth-decrease 0.00003 * resolution ; pls decrease when encountering problem youth is the same as the increase when citizens meet a community worker or a police man
  set pls-litter-decrease 0.00001 * resolution ; pls decrease when encountering litter is the same as when they meet another citizen
  set pls-burglary-decrease 10 ; burglaries decrese the pls by a lot


  set qr-scanning-chance 0.002 * resolution ; qr-code scanning chance
  set community-center one-of patches with [category = "community centre"]

end



to go
  ; do timekeeping
  do-timekeeping
  ; stop simulation after 3 years
  if (totaldays > 3 * 365) [stop]
  ; update pls average
  set pls-average mean [pls] of citizens
  set viability-average mean [viability] of patches with [category = "neighbourhood initiative"]

  ; let all turtles live their lifes and do their jobs (citizens, community workers, police)
  ask citizens [live-life]
  ask community-workers [do-community-worker-job]
  ask problem-youth [hang-around]
  ask police-officers [do-police-job]
  ask waste-collectors [collect-waste]

  ; ask all turtles to interact with each other
  ask turtles [interact]

  tick ; next time step
end


to do-timekeeping
  ifelse (tickstoday < ticksperday)
  ; in case the day is not yet finished
  [set tickstoday tickstoday + 1]

  ; in case the day is finished, advance one day and let citizens reschedule their day
  [
    set tickstoday 0 ; reset ticks of the day
    set totaldays totaldays + 1 ; add one day to the total number of days

    ; in case it is sunday, set day to monday, otherwise increse weekday count
    ifelse (day = 7) [ set day 1]
    [ set day day + 1 ]

    ;let all turtles schedule their day (and citizens to possibly start an initiative, if conditions are given
    ask citizens [
      schedule-citizen-day
      start-initiative
    ]
    ask community-workers [ schedule-community-worker-day ]

    ; let the daily crimes occur and litter be produced
    setup-crimes
    setup-litter
    ask police-officers [ schedule-police-officer-day ]

    ;handle the initiative time
    ask patches with [category = "neighbourhood initiative"] [
      ifelse (initiative-time > 26 * 7) or (viability <= 0) [
        ; If  the initiative is older than half a year or the viability is below 0, let it die
        set category 0
        set initiative-time 0
        set viability 0

        ; remove all citizens from that initiative
        ask citizens with [initiative = myself][
          set part-of-initiative False
          set initiative 0


        ]
        ; create a random amount of problem youth (between 0 and 5)
        sprout-problem-youth random 6 [
          setxy random-pxcor random-pycor
          set shape "problem youngster"
          set size 15
          set speed 2 * resolution
          set target-patch min-one-of (patches with [category = "school" or category = "supermarket"]) [distance myself]
        ]

      ][
        ; Else increase the time that the initiative existed and decrease the viability
        set initiative-time initiative-time + 1
        set viability viability - 1
      ]
    ]
  ]

end

to-report monitor-time
  report (word "Day (1 = Mo, 7 = Sun): " day " Time:" (floor (tickstoday * resolution / 60)) "\n Total Days: " totaldays)

end


to interact

  let citizens-to-interact citizens in-radius 1  ; create an agentset with all citizens in a given radius

  ; take the variable from the slider as a basic interaction chance for citizens & make it dependent on the average pls, which caps the pecentage of interactions possible
  let chance-to-interact ((interaction-chance / 100) * (pls-average / 100))
  if breed = community-workers [set chance-to-interact 1] ; community workers will always speak to citizens
  if breed = police-officers [set chance-to-interact (1 - (pls-average / 100))] ; police workers solely interact upon the average perceived pls (always interact when average is 0, never interact when average is 100
  if breed = waste-collectors [set chance-to-interact 0] ; no interaction possible with waste collectors

  ; only do interactions if there are agents to interact with and the chance of interaction is fulfilled
  if (any? citizens-to-interact) and (random-float 1 < chance-to-interact) [
    let citizen-to-interact one-of citizens-to-interact ;select one person to interact with

    ;in case a community worker likes to interact, prefer citizens that are part of an initiative
    if breed = community-workers and any? citizens-to-interact with [part-of-initiative] [set citizen-to-interact one-of citizens-to-interact with [part-of-initiative]]

    ifelse (breed = citizens) [
      set pls min list (100) (pls + pls-increase-little)  ; higher own pls by a little, if interaction is successful
      ask citizen-to-interact [
        set pls min list (100) (pls + pls-increase-little)
        set interactions interactions + 1
      ] ; higher the pls of the other person by a little
    ] [
      ask citizen-to-interact [
        set pls min list (100) (pls + (3 * pls-increase-little))
        set interactions interactions + 1
      ]
    ] ; higher the amount of pls of the other person by a lot
  ]

  ; Experience litter and problem youth
  if (breed = citizens and any? problem-youth in-radius 5) [set pls max list (0) (pls - pls-problem-youth-decrease)]
  if (breed = citizens and any? patches in-radius 5 with [pcolor <= 39 and pcolor >= 31]) [set pls max list (0) (pls - pls-litter-decrease)]
end




;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Citizen Functions-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

to setup-citizens
  create-citizens number-citizens [
    set house one-of patches with [pcolor = 7.9] ; remember the home location of the agent
    setxy [pxcor] of house [pycor] of house
    set children random-float 1 < 0.6 ; chance that one citizen has children is 60%
    set job random-float 1 < 0.6 ; chance that one citizen has a job is 60% as well
    set religious random-float 1 < 0.5 ; chance that one citizen is religious is 50%
    set pls  min list 100 (max list (0) (random-normal 40 10)) ;
    set qrcodes-scanned max list (0) (round random-normal 15 10); assumption: in the beginning, each citizen scanned around 5-25 QR codes
    set initiative-threshold random-normal 40 5 ; assumption: a citizens needs around 35-45 QR codes scanned to start an initiative
    set speed random-normal 3 1 * resolution ; speed depends on the resolution (unit: patch/minute)
    set interactions 0
    set shape "person"
    set size 5

    ; calculate the patch where the citizen works and where their children go to school
    if job [ set work min-one-of patches with [(pxcor = 0) or (pycor = 0) or (pxcor = 814) or (pycor = 784)] [distance myself] ]
    if children [set school min-one-of patches with [category = "school"] [distance myself] ]

    ; setup the schedule for each agent
    set schedule table:make
    let i 0
    repeat (ticksperday + 1) [
      table:put schedule i "home"
      set i i + 1
    ]

    ; setup the citizens who are part of an initiative (12%)
    ifelse (random-float 1 < 0.12) [
      set part-of-initiative True
      set initiative one-of patches with [category = "neighbourhood initiative"]
    ] [
      set part-of-initiative False
    ]

  ]

  ask citizens [ schedule-citizen-day ]

end

to live-life


  ;Get current activity from schedule
  let current-activity table:get schedule tickstoday

  ;Set the destination for this tick, default is citizen's house
  let destination house

  ; Make agent move depending on the current activity
  ifelse (current-activity = "work") [ set destination work][
    ifelse (current-activity = "school") [ set destination school][
      ifelse (current-activity = "shopping") [ set destination min-one-of patches with [category = "supermarket"] [distance myself]][
        ifelse (current-activity = "worship") [ set destination min-one-of patches with [category = "religious"] [distance myself]][
          if (current-activity = "initiative") [
            if part-of-initiative [ set destination initiative  ]
              ; If citizens are not yet part of an initiative, assign them to the closest
              let closest-initiative min-one-of patches with [category = "neighbourhood initiative"][distance myself]
              set part-of-initiative True
              set initiative closest-initiative
              set destination closest-initiative
  ]]]]]



  ; if the activity is walking, randomly roam around (but 1 tick slower than when having a destination)
  ifelse (destination = "walking") [
    right random 360
    fd speed - 1
  ] [
    ; else head towards the direction

    if patch-here != destination [
      ifelse distance destination > speed
      [ ; if the distance to the destination is greater than the current speed, move towards the destination
        face destination
        fd speed
      ] [ ;else go to the place
        move-to destination

        ; In case agent is at an initiative, higher the viability of the initiative
        if (current-activity = "initiative") [
          set pls min list (100) (pls + pls-increase-little)
          ask patch-here [set viability viability + viability-increase-little]
        ]
      ]
    ]
  ]

  ; Interaction algorithm
  interact


  ; QR code scanning algorithm

  ; In case they are willing to scan something
  if (random-float 1 < qr-scanning-chance) [
    ; In case there's any QR codes nearby
    if (count patches with [category != 0] in-radius 3  > 0) [
      ; Increase the QR code counter
      set qrcodes-scanned qrcodes-scanned + 1

      ; Handle PLS-increase (either none, little or medium)
      set pls (pls + random 3 * pls-increase-little)

    ]
  ]



end

to schedule-citizen-day []

  ; empty the schedule of the day
  let i 0
  repeat (ticksperday + 1) [
    table:put schedule i "house"
    set i i + 1
  ]

  let activities-today table:make
  let timescheduled 0

  ; in case of weekday, add the weekday activities
  if (day < 6)
  [
    ; in case the citizen has a job
    if (job)[
      let worktime random-normal 7 1
      table:put activities-today "work" worktime
      set timescheduled timescheduled + worktime
    ]

    ; in case the citizen has children
    if (children) [
      let schooltime random-normal 1 0.5
      table:put activities-today "school" schooltime
      set timescheduled timescheduled + schooltime
    ]
  ]

  ; applicable for all the days and based on chance
  ;worship
  if (religious and random 7 < 1) [
      let religioustime random-normal 1 0.5
      table:put activities-today "worship" religioustime
      set timescheduled timescheduled + religioustime
    ]

  ; shopping
  if (random 7 < 3) [
    let shoppingtime random-normal 1.5 0.5
    table:put activities-today "shopping" shoppingtime
    set timescheduled timescheduled + shoppingtime
  ]

  ; join intitative
  if  (random 7 < 1) [
    let initiativetime random-normal 2 0.5
    table:put activities-today "initiative" initiativetime
    set timescheduled timescheduled + initiativetime
  ]


  ; recreational walk
  if (random 7 < 2) [
    let walktime random-normal 2 0.5
    table:put activities-today "walking" walktime
    set timescheduled timescheduled + walktime
  ]


  ;get a start time for work, which is centered around the time they plan to soend on activities each day
  ; "center" of the day is at 1300 -> substract half of timescheduled from it

  let starttime round (((random-normal 13 1) - timescheduled / 2) * 60 / resolution)

  ;iterate over all activities
  let row 0
  let activity-list table:keys activities-today
  let duration-list table:values activities-today

  repeat table:length activities-today [
    ; get activity and duration
    let activity item row activity-list
    let duration item row duration-list

    ;schedule the activity in the daily schedule
    repeat round (duration * 60 / resolution) [
      ; insert the activity at the given time
      table:put schedule starttime activity

      ; increase starttime by one tick
      set starttime starttime + 1
    ]

    set row row + 1
  ]

  ; If agents have children, always pick them up around 17:00 - Override any other scheduled activities, because children are important!!
  if children [
    let pick-up-time (17 * 60 / resolution)

    repeat round (random-normal 1 0.5) * 60 / resolution[
      table:put schedule pick-up-time "school"
      set pick-up-time pick-up-time + 1
    ]

  ]



end

; Let citizen start an initiative
to start-initiative
  ;                                                                                                  Conditions:
  if ((qrcodes-scanned > initiative-threshold) and                                                   ;(1) Citizens must have scanned a certain number of QR codes,
    (random 100 + 1 > pls-average)  and                                                              ;(2) the higher the PLS, the lower the chance that one takes action and
    (number-supported-initiatives > count patches with [category = "neighbourhood initiative"] )) [  ;(3) the municipality must have capacity to support another initiative

    ; Start initiative at a random patch
    let new-initiative-patch patch random-pxcor random-pycor

    ; Setup the new initiative patch
    ask new-initiative-patch [
      set category "neighbourhood initiative"
      set viability floor (random-normal 30 5) ; give initiative an initial variable viability
      set initiative-time 0
    ]

    ; Let the agent join the initiative
    set part-of-initiative True
    set initiative new-initiative-patch


    ; Whenever a new initiative is started, reduce the number of problem youth
    ; ask n-of 5 problem-youngster [die]

  ]

end



;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Community Worker related Functions-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

to setup-community-workers
  create-community-workers number-cw [

    ;let them initially be at the community center all day long
    set schedule table:make
    let i 0
    repeat (ticksperday + 1) [
      table:put schedule i community-center
      set i i + 1
    ]
    set speed 3 * resolution
    set shape "person service"
    set size 10
  ]

  ask community-workers [ schedule-community-worker-day ]

end


to schedule-community-worker-day
  ; empty the schedule of the day
  let i 0
  repeat (ticksperday + 1) [
    table:put schedule i community-center
    set i i + 1
  ]

  ; Plan new day - Assumption: Community workers visit the initiatives randomly
  let workingday 8 ; hours
  let initiatives-to-visit 1 + random 3 ; between 1 and 3 initiatives per day
  let time-per-initiative workingday / initiatives-to-visit
  let starttime round ((random-normal 10 1) * 60 / resolution)

  ; Add initiatives to the schedule
  repeat initiatives-to-visit [
    let initiative-to-visit one-of patches with [category = "neighbourhood initiative"]
    repeat round (time-per-initiative * 60 / resolution)
    [
      ; insert the activity at the given time
      table:put schedule starttime initiative-to-visit

      ; increase starttime by one tick
      set starttime starttime + 1
    ]
  ]

end

to do-community-worker-job
  ;Get scheduled patch from community worker
  let scheduled-patch table:get schedule tickstoday

  ifelse distance scheduled-patch > speed [
    face scheduled-patch
    fd speed
  ] [
    move-to scheduled-patch
    ask scheduled-patch [set viability (viability + 2 * viability-increase-little)]
  ]

end


to setup-initiatives
  ; set initial viability of each initiative with a max of 100 and a min of 0
  ask patches with [category = "neighbourhood initiative"] [
    set viability min list 100 max list 0 floor random-normal 60 15
    set initiative-time 0
  ]

  ; set the global average for performace reasons
  set viability-average mean [viability] of patches with [category = "neighbourhood initiative"]

end





;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Police related Functions-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

to setup-crimes
  ; the surface area of Bouwlust is approximately 2.4 km2
  ; the poulation density of The Hague is 6523 people/km2
  ; the registered crimes for the city of The Hague are used as a proxy of burlaries, they are 0.0721 r.c./(person*year)
  ; Consequently, the number of crimes per year in Bowlust is: 0.0721*6523*2.4 r.c/year = 1128.74 rc/year
  ; or equivalently, a daily figure of 3.1 r.c./day
  ; note: this is only an average figure since using spacially and termporally averaged data as inputs. With these basic assumptions, we came up with the following formula:

 ; the number of crimes per day varies between 1 and 5, dependent on the overall average pls
  repeat round (1 - pls-average / 100) * ((random 3)) ; * number-citizens / 21000)
  [
    ; Determine the citizen that gets robbed by chance
    let citizen-robbed one-of citizens

    ; burglaries can occur only at citizens' homes
    let crime-location [house] of citizen-robbed

    let px-coord [pxcor] of crime-location
    let py-coord [pycor] of crime-location

    ; burglaries will be visualized as red patches on the map
    ask patch px-coord py-coord [ set pcolor red ]

    ; burglary will lower the citzen's pls at a very high amount
    ask citizen-robbed [set pls max list (0) (pls - pls-burglary-decrease)]
  ]
  ; show crimes-list
end

to setup-litter

  ; the number of litter is randomly assigned between 0 and 19 patches, but then fractioned by the overall average pls. The higher the average pls, the less litter is there.
  let possible-locations patches with [pcolor = 9.1]
  repeat round (1 - pls-average / 100) * (random 20)
  [
    ; new litter locations are assumed to possibly occur only on streets or vegetation areas.
    let litter-location one-of possible-locations

    ; litter locations will be visualized as light brown patches
    ask patch random-pxcor random-pycor [ set pcolor 39 ]
  ]
  ; litter locations that have not been cleaned up previously will become of significant amount of litter
  ; and will be visualized as dark brown patches
  ask patches with [pcolor <= 39 and pcolor >= 31] [ set pcolor pcolor - 1 ]

end



to setup-problem-youth [number]
  create-problem-youth item 0 number [
    setxy random-pxcor random-pycor
    set shape "problem youngster"
    set size 10
    set speed 2 * resolution
    set target-patch min-one-of (patches with [category = "school" or category = "supermarket"]) [distance myself]

  ]
end




to hang-around
  ; problem youth moves from one preferred hotspot to another, where preferred hotspots
  ; are defined as schools or shopping malls (the latter being categorized as supermarkets)

  ; as long as a problem youngster feels lonely it will get closer to others to form a group, with which to hang out
  ; if the group is not too large nor too small, problem youth selects a the closest preferred hotspot where to hang out
  let neighbors-total count other problem-youth in-radius 4

  if patch-here = target-patch
  [
    if random 100 > 90
    [ if any? patches in-radius 3 with [pcolor = 9.1] and random 100 > 80
      [ask one-of patches in-radius 3  with [pcolor = 9.1] [set pcolor 39] ]
    ]
    ; if the group is too large it splits into two
    if neighbors-total > 20
    [
      ; identify two possible locations where to go next, so that the original group splits into two
      let possible-locations n-of 2 patches with [category = "school" or category = "supermarket"]
      let alternative-target-patch one-of possible-locations

      ask n-of 10 problem-youth in-radius 4 [
        set target-patch alternative-target-patch  ; half of the agents will pick one location and half the other

        ifelse distance target-patch > speed
        [
          face target-patch
          fd speed
        ][
          move-to target-patch
        ]
      ]


    ]
  ]

  ifelse distance target-patch > speed
  [
    face target-patch
    fd speed
  ][
    move-to target-patch
  ]




end

; police officers functions -----------------------------------------------------------------

to setup-police
  create-police-officers  number-police-officers
  [
    setxy police-xcor police-ycor
    set station patch-here ; remember the home location of the agent

    ;create an initial schedule for the first day of work, it will be then updated
    set schedule table:make
    let i 0
    repeat (ticksperday + 1)
    [
      table:put schedule i station
      set i i + 1
    ]

    set shape "person police"
    set size 10
    set speed 3 * resolution
  ]
  ; for the day 0 ask police officers to compose their first schedule
  ask police-officers [ schedule-police-officer-day ]

end

to schedule-police-officer-day ; we use turtle-id because the ids of turtles are unique, regardless of the turtle's breed
                                           ; this procedure will be called for each police officer agent of the police-officers agentset at the start of each day

  ; since this procedure is called for day 0 and also for each other day, we here empty the schedule of the day (from the previous day's activities)
  let i 0
  repeat (ticksperday + 1)
  [
    table:put schedule i station
    set i i + 1
  ]


  ; Plan a police-officer's shift
  ; for all crimes, a visit by a police officer is scheduled and will be executed as the shift starts
  ; in the do-police-job procedure. In this way, crimes are assumed to have the highest priority
  let shift 9 ; hours. When the shift ends, police officers go back to the station
  let time-per-crime 2 ; [hours]
  let time-per-round 1 ; [hours]
  let start-time round ((random-normal 8 1)  * 60 / resolution) ; [ticks],  the shift starts at 8:00
  let end-shift start-time + ( shift * 60 / resolution ) ; [ticks]

  ; if crimes were committed on the current day, police officers schedule to go there during the day
  ; crime locations are scheduled until either the officer schedule is full or there are no more crime locations to visit
  while [start-time <= end-shift and any? patches with [ pcolor = red ] ]
  [

   ; create an agentset containing all the crime patches and select one of them to be put in the officer's schedule
   let crimes patches with [ pcolor = red ]
   let selected-crime one-of crimes

   ; schedule the selected crime in the officer's daily schedule for all its relative duration
   repeat round (time-per-crime * 60 / resolution)
   [
     table:put schedule start-time selected-crime

     ; increase starttime by one tick
     set start-time start-time + 1
   ]

    ; restore the original color of the patch after the crime is scheduled to be taken care of
    ask selected-crime [ set pcolor 7.9 ]

    ; If any, the remaining time of a shift, after visiting all crime locations, is devoted to doing rounds
    ; the round content will be specified in the do-police-job procedure
    while [start-time <= end-shift ]
    [
      repeat round (time-per-round * 60 / resolution)
      [
      table:put schedule  start-time "round"
      set start-time start-time + 1
      ]
    ]

  ]

end



to do-police-job
  ;This procedure is called at each tick, therefore we use the current tick to find the activity to perform
  let activity table:get schedule tickstoday

  ;in the officer's schedule (which is a police-officer's own variable) there are either patches or "round" strings.
  ;if the activity is a crime-location patch treat it as a location where to go to
  ifelse activity != "round"
  [
    ;go to the crime location scheduled for the current tick
    ifelse distance activity > speed
    [
      face activity
      fd speed
    ][
      move-to activity
      ask citizens with [house = patch-here] [set pls (pls + 3 * pls-increase-little)]
    ]

  ][;if the activity is a "round" string, visit the nearest significant litter or problem youth location

    let next-target-patch min-one-of ( (patch-set patches with [pcolor >= 31 and pcolor <= 33] [patch-here] of problem-youth) ) [distance myself]
    if next-target-patch != nobody
    [
      ifelse distance next-target-patch > speed
      [
        face next-target-patch
        fd speed
      ][
        move-to next-target-patch

        ; cause problem youth to run away to another hotspot
        if any? problem-youth in-radius 4
        [ask problem-youth in-radius 4 [
          let alternative-target-patch one-of patches with [category = "school" or category = "supermarket"]
          set target-patch alternative-target-patch
          face target-patch
          fd speed * 2
          ]
        ]
      ]
    ]
  ]

end


to setup-waste-collectors

  create-waste-collectors number-waste-collectors [
    ; setxy random-pxcor random-pycor will be done in the collect-waste procedure at each start of the working day
    set shape "person waste-collector"
    set size 10
    set start-working-day round (random-normal 9 1 * 60 / resolution) ; [ticks]
    set end-working-day (start-working-day + 8 * 60 / resolution) ; [ticks] the working day length is set to 8 hours
    set speed 3 * resolution
    ]

end

to collect-waste
  if tickstoday = start-working-day
  [
    ; the waste-collector comes at a radndom location of the map determined by the external waste-collecting scheduling and logic (treated as part of the environment for this model)
    set hidden? False
    setxy random-pxcor random-pycor
  ]
  if tickstoday > start-working-day and tickstoday < end-working-day
  [
    let litter-location min-one-of (patches with [pcolor >= 31 and pcolor <= 39 ]) [distance myself]

    if litter-location != nobody
    [
      ifelse distance litter-location > speed
      [
        face litter-location
        fd speed
      ][
        move-to litter-location
        ask patch-here [set pcolor 9.1]
        ask patches in-radius (speed / 2) with [pcolor >= 31 and pcolor <= 39 ]

      ]
    ]
  ]
  if tickstoday = end-working-day
  [set hidden? True]

end
@#$#@#$#@
GRAPHICS-WINDOW
549
10
1372
804
-1
-1
1.0
1
10
1
1
1
0
0
0
1
0
814
0
784
1
1
1
ticks
30.0

BUTTON
11
40
84
73
NIL
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
96
41
159
74
NIL
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
1

SWITCH
12
122
133
155
verbose?
verbose?
1
1
-1000

SWITCH
140
123
250
156
debug?
debug?
1
1
-1000

SLIDER
11
160
195
193
resolution
resolution
5
60
45.0
5
1
minutes/tick
HORIZONTAL

SLIDER
10
282
280
315
number-cw
number-cw
0
10
3.0
1
1
Community workers
HORIZONTAL

SLIDER
10
318
279
351
number-police-officers
number-police-officers
0
10
2.0
1
1
Officers
HORIZONTAL

MONITOR
9
448
412
493
Timekeeping
monitor-time
17
1
11

PLOT
10
496
412
616
Average PLS and Viability
Time [Ticks]
Via/PLS
0.0
10.0
0.0
100.0
true
true
"" ""
PENS
"Average Initiative Viability" 1.0 0 -16777216 true "" "plot viability-average"
"Average PLS" 1.0 0 -13840069 true "" "plot pls-average"

TEXTBOX
13
104
163
122
General Settings
11
0.0
1

TEXTBOX
13
265
163
283
Policy Levers
11
0.0
1

SLIDER
9
393
282
426
number-waste-collectors
number-waste-collectors
0
10
4.0
1
1
Waste collectors
HORIZONTAL

SLIDER
10
196
192
229
interaction-chance
interaction-chance
0
100
20.0
1
1
%
HORIZONTAL

SLIDER
10
355
279
388
number-supported-initiatives
number-supported-initiatives
0
10
5.0
1
1
Initiatives
HORIZONTAL

PLOT
301
280
501
430
Histogram of citizen's pls
NIL
NIL
0.0
100.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 true "" "histogram [pls] of citizens"

BUTTON
380
150
513
183
NIL
execute-profiler
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person police
false
0
Polygon -1 true false 124 91 150 165 178 91
Polygon -13345367 true false 134 91 149 106 134 181 149 196 164 181 149 106 164 91
Polygon -13345367 true false 180 195 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285
Polygon -13345367 true false 120 90 105 90 60 195 90 210 116 158 120 195 180 195 184 158 210 210 240 195 195 90 180 90 165 105 150 165 135 105 120 90
Rectangle -7500403 true true 123 76 176 92
Circle -7500403 true true 110 5 80
Polygon -13345367 true false 150 26 110 41 97 29 137 -1 158 6 185 0 201 6 196 23 204 34 180 33
Line -13345367 false 121 90 194 90
Line -16777216 false 148 143 150 196
Rectangle -16777216 true false 116 186 182 198
Rectangle -16777216 true false 109 183 124 227
Rectangle -16777216 true false 176 183 195 205
Circle -1 true false 152 143 9
Circle -1 true false 152 166 9
Polygon -1184463 true false 172 112 191 112 185 133 179 133
Polygon -1184463 true false 175 6 194 6 189 21 180 21
Line -1184463 false 149 24 197 24
Rectangle -16777216 true false 101 177 122 187
Rectangle -16777216 true false 179 164 183 186

person service
false
0
Polygon -7500403 true true 180 195 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285
Polygon -1 true false 120 90 105 90 60 195 90 210 120 150 120 195 180 195 180 150 210 210 240 195 195 90 180 90 165 105 150 165 135 105 120 90
Polygon -1 true false 123 90 149 141 177 90
Rectangle -7500403 true true 123 76 176 92
Circle -7500403 true true 110 5 80
Line -13345367 false 121 90 194 90
Line -16777216 false 148 143 150 196
Rectangle -16777216 true false 116 186 182 198
Circle -1 true false 152 143 9
Circle -1 true false 152 166 9
Rectangle -16777216 true false 179 164 183 186
Polygon -2674135 true false 180 90 195 90 183 160 180 195 150 195 150 135 180 90
Polygon -2674135 true false 120 90 105 90 114 161 120 195 150 195 150 135 120 90
Polygon -2674135 true false 155 91 128 77 128 101
Rectangle -16777216 true false 118 129 141 140
Polygon -2674135 true false 145 91 172 77 172 101

person waste-collector
false
0
Rectangle -7500403 true true 123 76 176 95
Polygon -1 true false 105 90 60 195 90 210 115 162 184 163 210 210 240 195 195 90
Polygon -13345367 true false 180 195 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285
Circle -7500403 true true 110 5 80
Line -16777216 false 148 143 150 196
Rectangle -16777216 true false 116 186 182 198
Circle -1 true false 152 143 9
Circle -1 true false 152 166 9
Rectangle -16777216 true false 179 164 183 186
Polygon -955883 true false 180 90 195 90 195 165 195 195 150 195 150 120 180 90
Polygon -955883 true false 120 90 105 90 105 165 105 195 150 195 150 120 120 90
Rectangle -16777216 true false 135 114 150 120
Rectangle -16777216 true false 135 144 150 150
Rectangle -16777216 true false 135 174 150 180
Polygon -955883 true false 105 42 111 16 128 2 149 0 178 6 190 18 192 28 220 29 216 34 201 39 167 35
Polygon -6459832 true false 54 253 54 238 219 73 227 78
Rectangle -16777216 true false 15 225 105 255

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

problem youngster
false
1
Circle -7500403 true false 110 5 80
Polygon -7500403 true false 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true false 127 79 172 94
Polygon -7500403 true false 195 90 240 150 225 180 165 105
Polygon -7500403 true false 105 90 60 150 75 180 135 105
Polygon -2674135 true true 120 15 135 30 195 30 210 15 180 15 165 0 135 0

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="BaseCase" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>mean [pls] of citizens</metric>
    <metric>mean [interactions] of citizens</metric>
    <metric>mean [qrcodes-scanned] of citizens</metric>
    <enumeratedValueSet variable="debug?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-cw">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verbose?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="resolution">
      <value value="45"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-police-officers">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-supported-initiatives">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-waste-collectors">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="interaction-chance">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-seed">
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
