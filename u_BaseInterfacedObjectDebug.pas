unit u_BaseInterfacedObjectDebug;

interface

uses
  i_InterfaceListSimple,
  i_InternalPerformanceCounter,
  i_InternalPerformanceCounterListForDebug;

type
  TBaseInterfacedObjectDebug = class(TInterfacedObject)
  private class var
    FCountersFindCounter: IInternalPerformanceCounter;
    FCounters: IInternalPerformanceCounterListForDebug;
  private
    class function GetCounter: IInternalPerformanceCounterListForDebugOneClass; virtual;
    function GetRefCount: Integer;
  private
    FContext: TInternalPerformanceCounterContext;
    FCounter: IInternalPerformanceCounter;
  protected
    function _AddRef: Integer; stdcall;
  public
    class procedure AddStaticDataToList(const AList: IInterfaceListSimple);
    class procedure InitCounters;
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;
    property RefCount: Integer read GetRefCount;
  end;

implementation

uses
  SysUtils,
  u_InternalPerformanceCounter,
  u_InternalPerformanceCounterListForDebug;

resourcestring
  rsDoubleFree = 'Double Free: Object is olready deleted!';
  rsInvalidDelete = 'Invalid Delete: Object is still have active interface ref''s! (Ref count: %d)';
  rsUseDeleted = 'Use Deleted: Object is not exists!';

const
  cUndefRefCount = -1;

{ TBaseInterfacedObjectDebug }

class procedure TBaseInterfacedObjectDebug.AddStaticDataToList(
  const AList: IInterfaceListSimple
);
begin
  if Assigned(AList) then begin
    if Assigned(FCountersFindCounter) then begin
      AList.Add(FCountersFindCounter.GetStaticData);
    end;
    if Assigned(FCounters) then begin
      FCounters.AddStaticDataToList(AList);
    end;
  end;
end;

procedure TBaseInterfacedObjectDebug.AfterConstruction;
begin
  inherited;
  if FCounter <> nil then begin
    FCounter.FinishOperation(FContext);
    FCounter := nil;
  end;
end;

procedure TBaseInterfacedObjectDebug.BeforeDestruction;
var
  VList: IInternalPerformanceCounterListForDebugOneClass;
begin
  if FRefCount < 0 then begin
    raise Exception.Create(rsDoubleFree);
  end else if FRefCount <> 0 then begin
    raise Exception.CreateFmt(rsInvalidDelete, [FRefCount]);
  end;
  inherited BeforeDestruction;
  FRefCount := cUndefRefCount;

  VList := GetCounter;
  if VList <> nil then begin
    FCounter := VList.CounterDestroy;
    FContext := FCounter.StartOperation;
  end;
end;

function TBaseInterfacedObjectDebug.GetRefCount: Integer;
begin
  if FRefCount < 0 then begin
    Result := 0;
  end else begin
    Result := FRefCount;
  end;
end;

function TBaseInterfacedObjectDebug._AddRef: Integer; stdcall;
begin
  if FRefCount < 0 then begin
    raise Exception.Create(rsUseDeleted);
  end;
  Result := inherited _AddRef;
end;

procedure TBaseInterfacedObjectDebug.FreeInstance;
var
  VCounter: IInternalPerformanceCounter;
  VContext: TInternalPerformanceCounterContext;
begin
  VCounter := FCounter;
  VContext := FContext;
  inherited;
  if VCounter <> nil then begin
    VCounter.FinishOperation(VContext);
  end;
end;

class function TBaseInterfacedObjectDebug.GetCounter: IInternalPerformanceCounterListForDebugOneClass;
var
  VCounter: IInternalPerformanceCounter;
  VContext: TInternalPerformanceCounterContext;
begin
  Result := nil;
  VContext := 0;
  VCounter := FCountersFindCounter;
  if Assigned(VCounter) then begin
    VContext := VCounter.StartOperation;
  end;
  try
    if FCounters <> nil then begin
      Result := FCounters.GetCounterByClass(Self);
    end;
  finally
    if Assigned(VCounter) then begin
      VCounter.FinishOperation(VContext);
    end;
  end;
end;

class procedure TBaseInterfacedObjectDebug.InitCounters;
var
  VFactory: IInternalPerformanceCounterFactory;
begin
  if FCounters <> nil then begin
    Assert(False);
  end else begin
    VFactory := TInternalPerformanceCounterFactory.Create;
    FCountersFindCounter := VFactory.Build('/ObjectsCountrFind');
    FCounters :=
      TInternalPerformanceCounterListForDebug.Create(
        '/Objects',
        VFactory
      );
  end;
end;

class function TBaseInterfacedObjectDebug.NewInstance: TObject;
var
  VList: IInternalPerformanceCounterListForDebugOneClass;
  VCounter: IInternalPerformanceCounter;
  VContext: TInternalPerformanceCounterContext;
begin
  VList := GetCounter;
  if VList <> nil then begin
    VCounter := VList.CounterCreate;
    VContext := VCounter.StartOperation;
    Result := inherited NewInstance;
    TBaseInterfacedObjectDebug(Result).FCounter := VCounter;
    TBaseInterfacedObjectDebug(Result).FContext := VContext;
  end else begin
    Result := inherited NewInstance;
  end;
end;

end.
