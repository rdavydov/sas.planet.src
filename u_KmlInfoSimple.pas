unit u_KmlInfoSimple;

interface

uses
  t_GeoTypes;

type
  TKMLData = record
    PlacemarkID: string;
    Name: string;
    description: string;
    coordinates: TExtendedPointArray;
    coordinatesLT: TExtendedPoint;
    coordinatesRD: TExtendedPoint;
    function IsEmpty: Boolean;
    function IsPoint: Boolean;
    function IsLine: Boolean;
    function IsPoly: Boolean;
  end;

  TKmlInfoSimple = class
  public
    Data: Array of TKMLData;
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TKmlInfoSimple);
  end;



implementation

{ TKmlInfoSimple }

procedure TKmlInfoSimple.Assign(Source: TKmlInfoSimple);
var
  VElementsCount: Integer;
  i: integer;
begin
  if Source <> nil then begin
    VElementsCount := length(Source.Data);
    SetLength(Data, VElementsCount);
    for i := 0 to VElementsCount - 1 do begin
      Data[i].PlacemarkID := Source.Data[i].PlacemarkID;
      Data[i].Name := Source.Data[i].Name;
      Data[i].description := Source.Data[i].description;
      Data[i].coordinatesLT := Source.Data[i].coordinatesLT;
      Data[i].coordinatesRD := Source.Data[i].coordinatesRD;
      Data[i].coordinates := Copy(Source.Data[i].coordinates);
    end;
  end;
end;

constructor TKmlInfoSimple.Create;
begin
  Data := nil;
end;

destructor TKmlInfoSimple.Destroy;
var
  i: integer;
begin
  if Data <> nil then begin
    for i := 0 to Length(Data) - 1 do begin
      Data[i].PlacemarkID := '';
      Data[i].Name := '';
      Data[i].description := '';
      Data[i].coordinates := nil;
    end;
  end;
  inherited;
end;

{ TKMLData }

function TKMLData.IsEmpty: Boolean;
begin
  Result := Length(coordinates) = 0;
end;

function TKMLData.IsLine: Boolean;
var
  VPointCount: Integer;
begin
  VPointCount := Length(coordinates);
  if VPointCount > 1 then begin
    Result := (coordinates[0].X <> coordinates[VPointCount - 1].X) or
      (coordinates[0].Y <> coordinates[VPointCount - 1].Y);
  end else begin
    Result := False;
  end;
end;

function TKMLData.IsPoint: Boolean;
begin
  Result := Length(coordinates) = 1;
end;

function TKMLData.IsPoly: Boolean;
var
  VPointCount: Integer;
begin
  VPointCount := Length(coordinates);
  if VPointCount > 1 then begin
    Result := (coordinates[0].X = coordinates[VPointCount - 1].X) and
      (coordinates[0].Y = coordinates[VPointCount - 1].Y);
  end else begin
    Result := False;
  end;
end;

end.
 