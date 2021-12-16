unit fyLib;

{$mode objfpc}

{=====================================================================

  This library uses synaSER to implement serial communictaion with the
  FT32XXS.  The communication link is established in the "initialization"
  part of this unit, and destroyed in its finalization.

  We communicate with the instrument using four functions defined here:

     0 Send command string with no response string expected.
         Handled by the function "Send."
     O Send command string and expect a response string in reply.
         Handled by the function "SendWithResponse."
     O Send a single byte
         Handled by the function "SendByte." This function is only used
         when loading a waveform into an arbitrary waveform memory.
     O Receive a string from the instrument.


  When receivng a string from the instrument is expected, the operation may
  time out if nothing is in fact received.  The length of the timeout period
  is defined as a constant "TimeOut: integer = 20" here.

======================================================================}

interface

uses
  Classes, SysUtils, synaser;
Type
 TChannels  = (CH1, CH2, STARTF, STOPF); {StartF and StopF used in sweep setup.}

 TStateRecord =  {the current settings of all controls are saved in this record.}
   record
     C1wave: integer;
     C1freq: double;
     C1amp:  double;
     C1Ofs:  double;
     C1Duty: double;

     C2wave: integer;
     C2freq: double;
     C2amp:  double;
     C2Ofs:  double;
     C2Duty: double;
     C2Phase: integer;

     SweepMode: integer;
     SwStartF: double;
     SwStopF:  double;
     SweepTime: integer;

     TrigSource: integer;
     TrigCount: integer;

     PulseWidth: double;
   end; {record}


var
 Ser: TBlockSerial;

 sParms: shortstring; {string parameter to be passed to instrument.}
 CState: TStateRecord; {current state of all programmable instrument controls.}
 StateFile: file of TStateRecord; {file of instrument states}
 Scale: integer; {Defines frequency scale factor:  Hz, KHz, MHz}
 WaveFileReady: boolean;
 ArbTarget: byte;
 bhi, blo: array[1..2048] of byte; {Storage for bytes of arbitrary waveform.}
 sReceived: shortstring;

Const
 TimeOut = 50;
 sNoResponse = 'No response.';

procedure Send(Command: string);
procedure SendByte(b: byte);
function  SendWithResponse(Command: string): string;
function  Receive: string;

function  FrequencySet(CH: TChannels; Frequency: double): boolean;
    {Handle frequency setting for both channels and sweep start and stop}
function  WaveformSet(Ch: TChannels; Waveform: integer): boolean;
    {Set waveform for a channel (CH1 or CH2).  See notes for waveforms.}
function  AmplitudeSet(CH: TChannels; Level: double): boolean;
    {Set amplitude for a channel (CH1 or CH2).}
function  OffsetSet(CH: TChannels; Offset: double): boolean;
    {Set offset  for a channel (CH1 or CH2).}
function  DutyCycleSet(CH: TChannels; DutyCycle: double): boolean;
    {Set duty cycle for a channels (CH1 or CH2).}

{Can only set phase programmatically for channel 2}
function  PhaseSet(Phase: integer): boolean;
    {Set phase for CH2 relative to CH1. Can only be set by program for CH2.}

function  SweepTimeSet(aTime: integer): boolean;
function  SweepModeSet(mode: integer): boolean;
    {Sweep frequencies are set using the "FrequencySet" function above.}
procedure StartSweep;
    {Start sweep action.}
procedure PauseSweep;
    {Stop sweep action.  No way to juist "pause" it as far as I know although it
     can be done manually.}

function  TriggerSourceSet(Source: integer): boolean;
function  TrigCountSet(Count: integer): boolean;

function  PulseWidthSet(Width: double): boolean;

procedure CounterClear;
function GetCount: string;
function GetExtF: string;
function GetCh1F: string;

function ArbWaveLoaded(FileName: string): boolean;
function ArbWaveStored: boolean;

function  SaveState(InMemory: integer): boolean;
    {Save the current instrument state to a disk file.}
function  LoadState(FromMemory: integer): boolean;
    {Load a stored instrument state from a disk file.}

implementation
//Uses Main;

procedure Send(Command: string);
begin
 Ser.SendString(Command+#10);
end;

procedure SendByte(b: byte);
begin
 Ser.SendByte(b);
end;

function SendWithResponse(Command: string): string;
var S: String;
begin
 S := sNoResponse;
 Ser.SendString(Command+#10);
 sleep(50);
 S := Ser.RecvPacket(TimeOut);
// S := Ser.RecvTerminated(TimeOut,#10);
 result := S
end;

function  Receive: string;
Var S: String;
begin
 S := sNoResponse;
 S := Ser.RecvTerminated(TimeOut,#10);
 result := S;
end;

function WaveformSet(CH: TChannels; Waveform: integer): boolean;
{Returns true if wafeform is set, false otherwise}
begin
 if ((Waveform <= 20) and (Waveform >= 0)) then
  begin
   sParms := IntToStr(Waveform);
   Case CH of
    CH1:  begin CState.C1Wave := Waveform; send('bw'+sParms) end;
    CH2:  begin CState.C2Wave := Waveform; send('dw'+sParms) end;
   end;
   result := true;
  end
 else Result := false;
end;

function FrequencySet(CH: TChannels; Frequency: double): boolean;
{Returns true if frequency is set, false otherwise}
var F: integer;
begin
 If ((Frequency <= 24e6) and (Frequency >= 0.01)) then
  begin
   F := trunc(Frequency*100);
   sParms := IntToStr(F);
   while length(sParms) < 9 do sParms := '0'+sParms;
   Case CH of
    CH1:  begin CState.C1Freq := Frequency; Send('bf'+sParms) end;
    CH2:  begin CState.C2Freq := Frequency; Send('df'+sParms) end;
    STARTF: begin CState.SwStartF := Frequency; Send('bb'+sParms) end;
    STOPF:  begin CState.SwStopF  := Frequency; Send('be'+sParms) end;
   end; {case}
   result := true
  end
 else result := false;
end;

function AmplitudeSet(CH: TChannels; Level: double): boolean;
{Returns true if amplitude is set, false otherwise}
begin
 if ((Level <= 20.0) and (Level >= 0.01)) then
  begin
   Level := (Trunc(Level*100)/100);
   sParms := FloatToStrF(Level,ffFixed,5,2);
   Case CH of
    CH1:  Begin CState.C1Amp := level; Send('ba'+sParms) end;
    CH2:  Begin CState.C2Amp := level; Send('da'+sParms) end;
   end; {case}
   result := true
  end
 else result := false;
end;

function OffsetSet(CH: TChannels; Offset: double): boolean;
{Returns true if offset is set, false otherwise}
begin
 if ((Offset <= 10.0) and (Offset >=- 10.0)) then
  begin
   Offset := (Trunc(Offset*100)/100);
   sParms := FloatToStrF(Offset,ffFixed,5,2);
   Case CH of
    CH1:  Begin CState.C1Ofs := Offset; Send('bo'+sParms) end;
    CH2:  Begin CState.C2Ofs := Offset; Send('do'+sParms) end;
    end; {case}
   result := true
  end
 else result := false;
end;

function DutyCycleSet(CH: TChannels; DutyCycle: double): boolean;
{Returns true if Duty cycle is set, false otherwise}
begin
 if ((DutyCycle <= 100) and (DutyCycle >=0)) then
  begin
   DutyCycle := (Trunc(DutyCycle*10));
   sParms := FloatToStrF(DutyCycle,ffFixed,5,1);
   Case CH of
    CH1:  Begin CState.C1Duty := DutyCycle; Send('bd'+sParms) end;
    CH2:  Begin CState.C2Duty := DutyCycle; Send('dd'+sParms) end;
   end; {case}
   result := true
  end
 else result := false;
end;

function PhaseSet(Phase: integer): boolean;
{Phase = 20 delays the secondary wave relative to the primary wave.  The phase of
 the primary relative to the secondary can't be set programatically, but can be set
 manually.  Phase = 20 applied to the primary wave is the same as setting the phase
 of the secondary to 340 degrees.}
begin
 if ((Phase <= 359) and (Phase >=0)) then
  begin
   sParms := IntToStr(Phase);
   CState.C2Phase := Phase;
   Send('dp'+sParms);
   result := true
  end
 else result := false;
end;

function  SweepTimeSet(aTime: integer): boolean;
{Returns true if time is set, false otherwise}
begin
 if ((aTime <= 999) and (aTime >=0)) then
  begin
   sParms := IntToStr(aTime);
   CState.SweepTime := aTime;
   Send('bt'+sParms);
   result := true
  end
 else result := false;
end;

function SweepModeSet(mode: integer): boolean;
{Returns true if sweep mode is set, false otherwise}
begin
 result := true;
 if ((mode = 0) or (mode = 1)) then
  begin Send('bm'+IntToStr(mode)); CState.SweepMode := mode end
 else result := false;
end;

procedure StartSweep;
begin
 Send('br1')
end;

procedure PauseSweep;
begin
 Send('br0');
end;

function TriggerSourceSet(Source: integer): boolean;
begin
 result := true;
 case Source of
  0:  Send('tt0');
  1:  Send('tt1');
  2:  Send('tt2');
 else result := false;
 end; {case}
 if (result) then CState.TrigSource := Source;
end;

function TrigCountSet(Count: integer): boolean;
begin
 if((Count <= 1000000) and (Count > 0)) then
  begin
   sParms := IntToStr(Count);
   CState.TrigCount := Count;
   Send('tn'+sParms);
   result := true
  end
 else result := false;
end;

function PulseWidthSet(Width: double):boolean;
var PW: integer;
begin
 if ((Width <= 1e9) and (Width >= 10)) then
  begin
   PW := trunc(Width);
   CState.PulseWidth := PW;
   sParms := IntToStr(PW);
   while (length(sParms)< 10) do sParms := '0'+sParms;
   Send('bu'+sParms);
   result := true;
  end
 else result := false;
end;

procedure CounterClear;
begin
 Send('bc');
end;

function GetCount: string;
begin
 result := SendWithResponse('cc');
end;

function GetExtF: string;
begin
 result := SendWithResponse('ce');
end;

function GetCh1F: string;
begin
 result := SendWithResponse('cf');
// send('ce');
// sleep(20);
// result := ser.recvpacket(timeout);
end;


function ArbWaveLoaded(FileName: string): boolean;
var
 WaveFile: text;
 i: integer;
 S: string;
 y: double;
 yi: word;
begin
   AssignFile(WaveFile,FileName);
   Reset(WaveFile);
   i:= 1;
   WaveFileReady := false;
   while (not(EOF(WaveFile)) and (i <= 2048)) do
    begin
     readln(WaveFile,S);
     try
      y := StrToFloat(S);
     except
      exit;
     end;
     yi := round((Y+1)*2048);
     if (yi = 4096) then yi := 4095;
      begin
       bhi[i] := hi(yi);
       blo[i] := lo(yi);
      end;
     inc(i);
    end; {while}
   if ((i = 2049) and (EOF(WaveFile))) then WaveFileReady := True;
   CloseFile(WaveFile);
   result := WaveFileReady;
end;

Function ArbWaveStored: boolean;
var i: integer;
begin
 result := false;
 if (Not(SendWithResponse('DDS_WAVE'+char($A5)) = 'X')) then exit;
 if (Not(SendWithResponse('DDS_WAVE'+char($F0+ARBTarget)) = 'SE')) then exit;
 if (Not(SendWithResponse('DDS_WAVE'+char(ARBTarget)) = 'WX')) then exit;
 for i := 1 to 2048 do
  begin
   Ser.SendByte(bhi[i]);
   sleep(5);
   Ser.SendByte(blo[i]);
   sleep(5);
  end;
// if not(FMain.Responded('N')) then exit else result := True;
end;


function SaveState(InMemory: integer): boolean;
begin
 if ((InMemory <= 19) and (InMemory >= 0)) then
  begin
   sParms := IntToStr(InMemory);
   Send('bs'+sParms);
   AssignFile(StateFile,'PM'+IntToStr(InMemory));
   ReWrite(StateFile);
   Write(StateFile,CState);
   CloseFile(StateFile);
   result := true
  end
 else result := false;
end;

function LoadState(FromMemory: integer): boolean;
begin
 if ((FromMemory <= 19) and (FromMemory >= 0)) then
  begin
   sParms := IntToStr(FromMemory);
   Send('bl'+sParms);
   AssignFile(StateFile,'PM'+IntToStr(FromMemory));
   Reset(StateFile);
   Read(StateFile,CState);
   CloseFile(StateFile);
   result := true
  end
 else result := false;
end;

Initialization
 Ser:=TBlockSerial.Create;
 Ser.LinuxLock:=false;
 Ser.Connect('/dev/ttyUSB0');
 if Ser.Handle=INVALID_HANDLE_VALUE then
   raise Exception.Create('Could not open device '+ Ser.Device);
 Ser.Config(9600,8,'N',1,false,false);

finalization
if Ser.Handle<>INVALID_HANDLE_VALUE then
 begin
   Ser.Purge;
   Ser.CloseSocket;
 end;
Ser.Free;

end.

cf - query main channel freq. respose e.g. cf0000000050
cd - get main duty cycle - cd500
ce - get counter frequency response e.g. ce0000000000
cc - get counter count repsonse e.g. cc0000000000
ct - get sweep time xx e.g. ct10
bc - clear counter
