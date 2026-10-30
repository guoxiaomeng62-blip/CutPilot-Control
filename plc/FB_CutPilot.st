(* CutPilot PLC core logic template. Not commissioned for a physical machine. *)
FUNCTION_BLOCK FB_CutPilot
VAR_INPUT
    Start, Reset, Stop : BOOL;
    SafetyOK, AirOK, WasteBoxOK : BOOL;
    FeedHome, FeedWork, PressUp, PressDown : BOOL;
    HeadUp, HeadDown, VacuumOK, ReleaseOK : BOOL;
    XReady, XDone : BOOL;
    VisionDone, VisionValid, PositionOK : BOOL;
    HoleOK : ARRAY[1..5] OF BOOL;
    VisionDx, XPick, XGood, XReject, DxLimit : REAL;
END_VAR
VAR_OUTPUT
    FeedForward, FeedBackward : BOOL;
    PressDownCmd, PressUpCmd : BOOL;
    HeadDownCmd, HeadUpCmd : BOOL;
    VacuumOn, ReleaseCmd : BOOL;
    XExecute : BOOL;
    XTarget : REAL;
    VisionTrigger : BOOL;
    VisionMode : INT;
    Step, FaultCode : INT;
    GoodCount, RejectCount : DINT;
END_VAR
VAR
    StartEdge, ResetEdge : R_TRIG;
    StepTimer : TON;
    LastStep : INT;
    PieceOK : BOOL;
    PickTarget, PlaceTarget : REAL;
    i : INT;
END_VAR

StartEdge(CLK := Start);
ResetEdge(CLK := Reset);
StepTimer(IN := (Step <> 0) AND (Step <> 900)
                  AND (Step = LastStep), PT := T#10s);
LastStep := Step;

FeedForward := FALSE; FeedBackward := FALSE;
PressDownCmd := FALSE; PressUpCmd := FALSE;
HeadDownCmd := FALSE; HeadUpCmd := FALSE;
VacuumOn := FALSE; ReleaseCmd := FALSE;
XExecute := FALSE; VisionTrigger := FALSE;

IF NOT SafetyOK THEN
    FaultCode := 101; Step := 900;
ELSIF NOT AirOK OR NOT WasteBoxOK THEN
    FaultCode := 102; Step := 900;
ELSIF StepTimer.Q THEN
    FaultCode := 103; Step := 900;
END_IF;

CASE Step OF
0:  (* Wait for start; initial position must be confirmed. *)
    IF StartEdge.Q AND NOT Stop AND SafetyOK AND AirOK
       AND WasteBoxOK AND FeedHome AND PressUp AND HeadUp
       AND XReady AND (FaultCode = 0) THEN
        Step := 10;
    END_IF;
10: (* Position inspection; VisionDone must match this task. *)
    VisionMode := 1; VisionTrigger := TRUE;
    IF VisionDone THEN
        IF VisionValid AND PositionOK
           AND (ABS(VisionDx) <= ABS(DxLimit)) THEN
            PickTarget := XPick + VisionDx; Step := 20;
        ELSE
            FaultCode := 201; Step := 900;
        END_IF;
    END_IF;
20: FeedForward := TRUE;
    IF FeedWork AND PressUp AND HeadUp THEN Step := 30; END_IF;
30: FeedForward := TRUE; PressDownCmd := TRUE;
    IF PressDown THEN Step := 40; END_IF;
40: FeedForward := TRUE; PressUpCmd := TRUE;
    IF PressUp THEN Step := 50; END_IF;
50: FeedBackward := TRUE;
    IF FeedHome THEN Step := 60; END_IF;
60: (* Five-hole inspection. *)
    VisionMode := 2; VisionTrigger := TRUE;
    IF VisionDone THEN
        IF NOT VisionValid THEN
            FaultCode := 202; Step := 900;
        ELSE
            PieceOK := TRUE;
            FOR i := 1 TO 5 DO
                PieceOK := PieceOK AND HoleOK[i];
            END_FOR;
            IF PieceOK THEN PlaceTarget := XGood;
            ELSE PlaceTarget := XReject; END_IF;
            Step := 70;
        END_IF;
    END_IF;
70: XTarget := PickTarget; XExecute := TRUE;
    IF XDone THEN Step := 80; END_IF;
80: HeadDownCmd := TRUE; VacuumOn := TRUE;
    IF HeadDown AND VacuumOK THEN Step := 90; END_IF;
90: VacuumOn := TRUE; HeadUpCmd := TRUE;
    IF NOT VacuumOK THEN FaultCode := 301; Step := 900;
    ELSIF HeadUp THEN Step := 100; END_IF;
100: VacuumOn := TRUE; XTarget := PlaceTarget; XExecute := TRUE;
    IF NOT VacuumOK THEN FaultCode := 301; Step := 900;
    ELSIF XDone THEN Step := 110; END_IF;
110: VacuumOn := TRUE; HeadDownCmd := TRUE;
    IF NOT VacuumOK THEN FaultCode := 301; Step := 900;
    ELSIF HeadDown THEN Step := 120; END_IF;
120: HeadDownCmd := TRUE; ReleaseCmd := TRUE;
    IF ReleaseOK THEN Step := 130; END_IF;
130: HeadUpCmd := TRUE;
    IF HeadUp THEN Step := 140; END_IF;
140: XTarget := XPick; XExecute := TRUE;
    IF XDone THEN
        IF PieceOK THEN GoodCount := GoodCount + 1;
        ELSE RejectCount := RejectCount + 1; END_IF;
        Step := 0;
    END_IF;
900: (* Fault reset only after manual recovery to the initial state. *)
    IF ResetEdge.Q AND SafetyOK AND AirOK AND WasteBoxOK
       AND PressUp AND HeadUp AND FeedHome AND XReady THEN
        FaultCode := 0; Step := 0;
    END_IF;
END_CASE;

(* Cancel motion requests. Hardware determines safe valve/holding behavior. *)
IF Step = 900 THEN
    FeedForward := FALSE; FeedBackward := FALSE;
    PressDownCmd := FALSE; PressUpCmd := FALSE;
    HeadDownCmd := FALSE; HeadUpCmd := FALSE;
    XExecute := FALSE; VisionTrigger := FALSE; ReleaseCmd := FALSE;
END_IF;
END_FUNCTION_BLOCK
