unit ThreadBarrier;

interface

type
  ThreadBarrierStatus = (ThreadBarrierStatusOk, ThreadBarrierStatusSerial);

  IThreadBarrier = interface
    ['{06544DF9-4ED2-4708-845C-76AB4F46A373}']

    /// <summary>
    ///  Blocks until the required number of threads have called Wait on this barrier.
    ///  One of the threads will return ThreadBarrierStatusSerial, indicating that it can
    ///  update shared resources. The remaining threads will return ThreadBarrierStatusOk.
    /// </summary>
    function Wait: ThreadBarrierStatus;
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
  System.SysUtils, Winapi.Windows, System.SyncObjs;

type
  // simple wrapper
  TLock = record
  strict private
    FCritSection: TRTLCriticalSection;
    FPadding: array[0..(64 - SizeOf(TRTLCriticalSection))-1] of UInt8;
  public
    procedure Initialize;

    procedure Aquire;
    procedure Release;
  end;

{ TLock }

procedure TLock.Aquire;
begin
  EnterCriticalSection(FCritSection);
end;

procedure TLock.Initialize;
begin
  InitializeCriticalSection(FCritSection);
  FillChar(FPadding, SizeOf(FPadding), 0);
end;

procedure TLock.Release;
begin
  LeaveCriticalSection(FCritSection);
end;

type
  TThreadBarrierImpl = class(TInterfacedObject, IThreadBarrier)
  strict private
    FCurWaitThreadCount: integer;
    FThreadCount: integer;
    FBarrierEvents: TArray<THandle>;
    FBarrierLocks: TArray<TLock>;
  public
    constructor Create(const ThreadCount: integer);
    destructor Destroy; override;

    function Wait: ThreadBarrierStatus;
  end;

function NewThreadBarrier(const ThreadCount: integer): IThreadBarrier;
begin
  result := TThreadBarrierImpl.Create(ThreadCount);
end;

{ TBarrierImpl }

constructor TThreadBarrierImpl.Create(const ThreadCount: integer);
var
  i: integer;
  h: THandle;
begin
  inherited Create;

  if (ThreadCount <= 0) then
    raise EArgumentException.Create('Invalid ThreadCount');

  FCurWaitThreadCount := ThreadCount;
  FThreadCount := ThreadCount;

  SetLength(FBarrierEvents, ThreadCount);
  SetLength(FBarrierLocks, ThreadCount);
  for i := 0 to ThreadCount-1 do
  begin
    h := CreateEvent(nil, True, False, nil);
    if (h = 0) then
      RaiseLastOSError;

    FBarrierEvents[i] := h;

    FBarrierLocks[i].Initialize;
  end;
end;

destructor TThreadBarrierImpl.Destroy;
var
  i: integer;
begin
  for i := 0 to FThreadCount-1 do
  begin
    if (FBarrierEvents[i] <> 0) then
      CloseHandle(FBarrierEvents[i]);
  end;

  inherited;
end;

function TThreadBarrierImpl.Wait: ThreadBarrierStatus;
var
  curThreadIndex: integer;
  i: integer;
  wr: cardinal;
begin
  curThreadIndex := TInterlocked.Decrement(FCurWaitThreadCount);

  // too many thread entered
  if (curThreadIndex < 0) then
    raise EInvalidOpException.Create('Barrier.Wait');

  // enter the barrier lock for this index
  // prevents "re-entry" of another thread before
  // the ResetEvent call is made for this index
  FBarrierLocks[curThreadIndex].Aquire();

  if (curThreadIndex = 0) then
  begin
    result := ThreadBarrierStatusSerial;

    // the last thread, all the others are waiting for us
    // so current thread can set the wait thread counter
    // but aquire the lock first
    TInterlocked.Exchange(FCurWaitThreadCount, FThreadCount);
  end
  else
  begin
    result := ThreadBarrierStatusOk;
  end;

  // signal that this thread is ready
  SetEvent(FBarrierEvents[curThreadIndex]);

  try
    // wait for barrier events
    // can't use WaitForMultipleObjects because the ResetEvent
    // will cause threads not woken up yeat from the wait
    // to continue to wait
    // by looping in the opposide direction of how we set the events
    // we ensure that the event we reset has been
    // successfully waited on by all other threads
    for i := FThreadCount-1 downto 0 do
    begin
      wr := WaitForSingleObject(FBarrierEvents[i], INFINITE);

      if (wr <> WAIT_OBJECT_0) then
        RaiseLastOSError;
    end;
  finally
    ResetEvent(FBarrierEvents[curThreadIndex]);

    // release any threads waiting to enter the barrier
    FBarrierLocks[curThreadIndex].Release;
  end;
end;

end.
