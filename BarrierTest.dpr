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
      threadStatus := Barrier.Wait;

      s := 'Pass #1 ' + Name;
      if (threadStatus = ThreadBarrierStatusSerial) then
        s := s + ' ==> Serial (' + IntToStr(Barrier.CurrentPhase) + ')';
      Print(s);

      Sleep(200);

      threadStatus := Barrier.Wait;
      threadStatus := Barrier.Wait;

      threadStatus := Barrier.Wait;
      s := 'Pass #2 ' + Name;
      if (threadStatus = ThreadBarrierStatusSerial) then
        s := s + ' ==> Serial (' + IntToStr(Barrier.CurrentPhase) + ')';
      Print(s);
    end
end;

procedure Test;
var
  barrier: IThreadBarrier;
  mp: TProc;
  i, n: integer;
begin
  n := 50;

  barrier := NewThreadBarrier(n);

  for i := 1 to n-1 do
  begin
    TThread.CreateAnonymousThread(
      NewThreadProc(Barrier, Format('Thread %d', [i]))
    ).Start;
  end;

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
