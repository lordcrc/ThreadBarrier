program BarrierTest;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  ThreadBarrier in 'ThreadBarrier.pas';

var
  PrintLock: TObject;

procedure Print(const s: string);
begin
  TMonitor.Enter(PrintLock);
  WriteLn('[' + FormatDateTime('hh:mm:ss:zzz', Now) + '] ' + s);
  TMonitor.Exit(PrintLock);
end;

function NewThreadProc(const Barrier: IThreadBarrier; const Name: string): TProc;
begin
  result :=
    procedure
    var
      threadStatus: ThreadBarrierStatus;
      s: string;
    begin
      threadStatus := Barrier.Wait;
      s := Name + ' released';
      if (threadStatus = ThreadBarrierStatusSerial) then
        s := s + ' ==> Serial thread';
      Print(s);
    end
end;

procedure Test;
var
  barrier: IThreadBarrier;
  mp: TProc;
begin
  barrier := NewThreadBarrier(4);

  TThread.CreateAnonymousThread(
    NewThreadProc(Barrier, 'Thread 1')
  ).Start;

  TThread.CreateAnonymousThread(
    NewThreadProc(Barrier, 'Thread 2')
  ).Start;

  TThread.CreateAnonymousThread(
    NewThreadProc(Barrier, 'Thread 3')
  ).Start;

  mp := NewThreadProc(Barrier, 'Main thread');
  mp();
end;

begin
  try
    PrintLock := TObject.Create;
    Test;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

  ReadLn;
end.
