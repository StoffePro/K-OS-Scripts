function main {
    sas off.
    global desiredApoapsis is 80000.
    //global desiredClimbTWR is 1.75.
    global desiredClimbTWR is 2.
    global gravityTurnStyle is "Classic".
    global gravityTurnVel is 50.
    global progradeFollowVel is 150.
    global launchDirection is 90.

    global shipHasBarometer is false.
    list sensors in mySensors.
    for s in mySensors {
        if s:type = "PRES" {
            set shipHasBarometer to true.
            break.
        }
    }
    if not shipHasBarometer {
        print "We have looked for a barometer, but we think we forgot it at home.".
    }

    ON AG3 {
        print ship:angularmomentum.
        return true.
    }
    // ON AG2 {
    //     SHUTDOWN.
    // }

    doCountDown(10).
    doLaunch().
    local alreadySwitchedToOrbital is false.
    until ship:obt:apoapsis >= desiredApoapsis {
        doClimb().
        if gravityTurnStyle = "Classic" {
            if not alreadySwitchedToOrbital {
                if abs(vang(ship:srfprograde:vector, ship:prograde:vector)) < 1 {
                    print "Switching to orbital prograde.".
                    lock targetPitch to max(5, 90 - vang(ship:prograde:vector, ship:up:vector)).
                    set alreadySwitchedToOrbital to true.
                }
            }
        }
    }
    print "We're gonna make it.".
    lock throttle to 0.

    print "Trying to find circularization.".
    local circularizationNode is findCircularizationNode().
    print "Helm is ready.".
    print "Make it so. Engage.".
    executeNode(circularizationNode).
    print "Roundness achieved, cptn!".

    lock throttle to 0.
    lock steering to "kill".
    wait 2.
    unlock throttle.
    unlock steering.
    print "launch program finished.".
}
main().

function findCircularizationNode {
    local done is False.
    local delta is 100.

    local a is Node(time:seconds, 0, 0, 0).
    declare local b is a.

    until done {
        set b to improveCircularizationNode(a, delta).
        if b:tostring <> "false" {
            set a to b.
        } else if delta > 0.01 {
            set delta to delta / 10.
        } else {
            set done to True.
        }
    }
    return a.
}

function improveCircularizationNode {
    declare local parameter data.
    declare local dataEccentricity is 0.
    declare local parameter delta.
    declare local best is data.
    declare local bestEccentricity is 0.
    declare local cnode is data.
    declare local cnodeEccentricity is 0.

    add(best).
    set bestEccentricity to best:orbit:eccentricity.
    set dataEccentricity to bestEccentricity.
    remove(best).

    local candidates is list(
        list(time:seconds + data:eta + delta, data:radialout,         data:normal,         data:prograde        ),
        list(time:seconds + data:eta,         data:radialout + delta, data:normal,         data:prograde        ),
        //list(time:seconds + data:eta,         data:radialout,         data:normal + delta, data:prograde        ),
        list(time:seconds + data:eta,         data:radialout,         data:normal,         data:prograde + delta),
        list(time:seconds + data:eta - delta, data:radialout,         data:normal,         data:prograde        ),
        list(time:seconds + data:eta,         data:radialout - delta, data:normal,         data:prograde        ),
        //list(time:seconds + data:eta,         data:radialout,         data:normal - delta, data:prograde        ),
        list(time:seconds + data:eta,         data:radialout,         data:normal,         data:prograde - delta)
    ).

    for candidate in candidates {
        set cnode to Node(candidate[0], candidate[1], candidate[2], candidate[3]).
        if cnode:eta > 0 {
            add(cnode).
            set cnodeEccentricity to cnode:orbit:eccentricity.
            set cnodePeriapsis to cnode:orbit:periapsis.
            remove(cnode).

            if cnodeEccentricity < bestEccentricity and cnodePeriapsis > 70000 {
                set best to cnode.
                set bestEccentricity to cnodeEccentricity.
            }
        }
    }
    if bestEccentricity < dataEccentricity {
        return best.
    } else {
        return False.
    }
}

function getCurrentThrust {
    local sumThrust is 0.
    list engines in myEngines.
    for e in myEngines {
        set sumThrust to sumThrust + e:thrust.
    }
    return sumThrust.
}

function doLaunch {
    set targetPitch to 90.
    local startAlt is ship:altitude.

    lock throttle to calculateThrottle(desiredClimbTWR).
    lock steering to ship:facing.

    doSafeStage().

    wait until getCurrentThrust() > ship:MASS.
    print "Engines are running. Release the brakes!".
    doSafeStage().

    until ship:altitude >= startAlt + 50 {
        doClimb().
    }


    print "I think we're clear. Lets turn.".
    lock steering to heading(launchDirection, targetPitch).
    wait 2.
    until ship:angularmomentum:mag < 1 {
        doClimb().
    }
    // wait until ABS(90 - hdg) < 1.
    print "This should be the right way.".

    until ship:airspeed >= gravityTurnVel {
        doClimb().
    }

    if gravityTurnStyle = "CheersKevin" {
        print "We're entering a formula none of us could understand.".
        lock targetPitch to 88.963 -  1.03287 * ship:altitude^0.409511.
    } else if gravityTurnStyle = "magic" {
        set targetPitch to 87.
        until ship:altitude >= 1000 {
            doClimb().
        }
        print "We're entering a formula none of us could understand.".
        lock targetPitch to 223.553 - 19.5608 * ln(ship:altitude).
    }
    else if gravityTurnStyle = "Classic" {
        print "Pitching over a little bit.".
        set targetPitch to 85.
        until ship:airspeed > progradeFollowVel {
            doClimb().
        }
        print "Following surface prograde. Cross your fingers!".

        lock targetPitch to min(85, 90 - vang(ship:srfprograde:vector, ship:up:vector) + 2).
        until targetPitch <= 45 {
            doClimb().
        }
        lock targetPitch to max(30, min(45, 90 - vang(ship:srfprograde:vector, ship:up:vector) + 5)).
        until ship:altitude >= 37000 {
            doClimb().
        }
        lock targetPitch to max(5, 90 - vang(ship:srfprograde:vector, ship:up:vector)).
    }
}

function doClimb {
    list engines in myEngines.
    for e in myEngines {
        if e:ignition and e:flameout {
            doSafeStage().
            return.
        }
    }
}

function getCurrentUnthrottlableThrust {
    local res is 0.
    list engines in myEngines.
    for e in myEngines {
        if e:throttlelock and e:ignition and not e:flameout {
            set res to res + e:availablethrust.
        }
    }
    return res.
}

function getAvailableThrottlableThrust {
    local res is 0.
    list engines in myEngines.
    for e in myEngines {
        if (not e:throttlelock) and (e:ignition) and (not e:flameout) {
            set res to res + e:availablethrust.
        }
    }
    return res.
}

function calculateThrottle {
    parameter myTWR.

// just under 50Km on kerbin
    if shipHasBarometer and ship:sensors:pres < 0.01 {
        if defined alreadyMessaged and not alreadyMessaged {
            print "The air is so thin we're not afraid to floor it.".
            set alreadyMessaged to true.
        }
        return 1.
    } else {
        local availablethrottlethrust is getAvailableThrottlableThrust().
        if  availablethrottlethrust > 0 {
            local weight is (ship:mass * ship:body:mu / (ship:body:radius + ship:altitude)^2).
            local requiredThrottleThrust is weight * myTWR - getCurrentUnthrottlableThrust().

            return requiredThrottleThrust / availablethrottlethrust.
        } else {
            return 1.
        }
    }
}

function executeNode {
    declare local parameter nd is nextnode.

    add(nd).

    print "Node in: " + round(nd:eta) + ", DeltaV: " + round(nd:deltaV:mag).

    set max_acc to ship:maxthrust / ship:mass.
    set burn_duration to nd:DeltaV:mag / max_acc.
    print "Burn time estimated at " + round(burn_duration) + " seconds.".

    wait until nd:eta <= (burn_duration / 2 + 60).
    set np to nd:DeltaV.
    lock steering to np.

    wait until vang(np, ship:facing:vector) < 0.25.
    wait until nd:eta <= (burn_duration / 2).
    set tset to 0.
    lock throttle to tset.
    set done to False.
    set dv0 to nd:DeltaV.

    until done {
        set max_acc to ship:maxthrust / ship:mass.
        set tset to min(nd:DeltaV:mag / max_acc, 1).

        if vdot(dv0, nd:DeltaV) < 0 {
            print "End burn, remaining dv " + round(nd:DeltaV:mag, 1) + "m/s, vdot: " + round(vdot(dv0, nd:DeltaV), 1) + ".".
            lock throttle to 0.
            break.
        }

        if nd:DeltaV:mag < 0.1 {
            print "Finalizing burn, remaining dv " + round(nd:DeltaV:mag, 1) + "m/s, vdot: " + round(vdot(dv0, nd:DeltaV), 1) + ".".
            wait until vdot(dv0, nd:DeltaV) < 0.5.
            lock throttle to 0.
            print "End burn, remaining dv " + round(nd:DeltaV:mag, 1) + "m/s, vdot: " + round(vdot(dv0, nd:DeltaV), 1) + ".".
            set done to true.
        }
    }

    unlock steering.
    unlock throttle.
    wait 1.

    remove nd.

    set ship:control:pilotmainthrottle to 0.
}

function doCountDown {
    declare local parameter n is 5.
    //local p_n is 5.

    print("initializing launch sequence...").
    wait(1).

    until n < 1 {
        print("T - " + n).
        wait(1).
        set n to n - 1.
    }

    print("Make rocket go now!").
}

function doSafeStage {
    wait until stage:ready.
    stage.
}

