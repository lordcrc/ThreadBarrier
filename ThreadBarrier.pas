unit ThreadBarrier;

interface

type
  ThreadBarrierStatus = (ThreadBarrierStatusOk, ThreadBarrierStatusSerial);

  IThreadBarrier = interface
    ['{06544DF9-4ED2-4708-845C-76AB4F46A373}']

    function GetCurrentPhase: cardinal;

    /// <summary>
    ///  Blocks until the required number of threads have called Wait on this barrier.
    ///  One of the threads will return ThreadBarrierStatusSerial, indicating that it can
    ///  update shared resources. The remaining threads will return ThreadBarrierStatusOk.
    /// </summary>
    function Wait: ThreadBarrierStatus;

    property CurrentPhase: cardinal read GetCurrentPhase;
  end;

/// <summary>
///  Creates a new barrier.
///  <param name="ThreadCount">The number of threads that has to wait on
///   the barrier before the barrier is released.
///  </param>
/// </summary>
function NewThreadBarrier(const ThreadCount: integer): IThreadBarrier;

implementation

uses
  System.SysUtils, System.SyncObjs, Winapi.Windows;

type
  TThreadBarrierImpl = class(TInterfacedObject, IThreadBarrier)
  strict private
    FCurWaitThreadCount: array[0..1] of integer;
    FBarrierOpen: array[0..1] of boolean;
    FPhase: cardinal;
    FThreadCount: integer;
    FBarrierCS: TCriticalSection;
    FBarrierCV: array[0..1] of TConditionVariableCS;
  public
    constructor Create(const ThreadCount: integer);
    destructor Destroy; override;

    function GetCurrentPhase: cardinal;

    function Wait: ThreadBarrierStatus;
  end;

function NewThreadBarrier(const ThreadCount: integer): IThreadBarrier;
begin
  result := TThreadBarrierImpl.Create(ThreadCount);
end;

{ TBarrierImpl }

constructor TThreadBarrierImpl.Create(const ThreadCount: integer);
begin
  inherited Create;

  if (ThreadCount <= 0) then
    raise EArgumentException.Create('Invalid ThreadCount');

  FThreadCount := ThreadCount;
  FCurWaitThreadCount[0] := ThreadCount;
  FCurWaitThreadCount[1] := ThreadCount;

  FBarrierOpen[0] := False;
  FBarrierOpen[1] := False;

  FBarrierCS := TCriticalSection.Create;
  FBarrierCV[0] := TConditionVariableCS.Create;
  FBarrierCV[1] := TConditionVariableCS.Create;
end;

destructor TThreadBarrierImpl.Destroy;
begin
  FBarrierCV[0].Free;
  FBarrierCV[1].Free;
  FBarrierCS.Free;

  inherited;
end;

function TThreadBarrierImpl.GetCurrentPhase: cardinal;
begin
  result := FPhase;
end;

function TThreadBarrierImpl.Wait: ThreadBarrierStatus;
var
  phaseIndex: integer;
  curThreadIndex: integer;
  lastThreadThisPhase: boolean;
  wr: TWaitResult;
begin
  // by default we're just another thread
  result := ThreadBarrierStatusOk;

  // we share critical section to ensure one thread can't
  // get ahead of the others
  FBarrierCS.Enter;

  // the current phase index, so we can ping-pong the counters and cv's
  phaseIndex := FPhase and 1;
  try
    Dec(FCurWaitThreadCount[phaseIndex]);

    curThreadIndex := FCurWaitThreadCount[phaseIndex];

    // too many thread entered
    if (curThreadIndex < 0) then
      raise EInvalidOpException.Create('Barrier.Wait');

    if (curThreadIndex = 0) then
    begin
      // final thread is the serializer
      result := ThreadBarrierStatusSerial;
      // this marks the release of the other threads
      FBarrierOpen[phaseIndex] := True;
      // and thus starts the next phase
      FPhase := FPhase + 1;
    end
    else
    begin
      // wait for the barrier to open
      repeat
        wr := FBarrierCV[phaseIndex].WaitFor(FBarrierCS);
        if (wr <> wrSignaled) then
          raise ESyncObjectException.Create('CV error');
      until (FBarrierOpen[phaseIndex]);
    end;

  finally
    // this resets the counter
    // while allowing us to trigger the "last thread to leave" action
    Inc(FCurWaitThreadCount[phaseIndex]);

    // last thread resets open flag
    lastThreadThisPhase := (FCurWaitThreadCount[phaseIndex] = FThreadCount);
    if (lastThreadThisPhase) then
    begin
      FBarrierOpen[phaseIndex] := False;
    end;

    FBarrierCS.Release;

    if (result = ThreadBarrierStatusSerial) then
    begin
      // we've opened the barrier, time to wake the other threads
      FBarrierCV[phaseIndex].ReleaseAll;
    end;
  end;
end;

end.
