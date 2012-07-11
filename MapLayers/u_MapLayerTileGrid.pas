unit u_MapLayerTileGrid;

interface

uses
  GR32,
  GR32_Image,
  t_GeoTypes,
  i_NotifierOperation,
  i_ViewPortState,
  i_InternalPerformanceCounter,
  i_LocalCoordConverter,
  i_MapLayerGridsConfig,
  u_MapLayerBasic;

type
  TMapLayerTileGrid = class(TMapLayerBasicNoBitmap)
  private
    FConfig: ITileGridConfig;
    procedure OnConfigChange;
  protected
    procedure PaintLayer(
      ABuffer: TBitmap32;
      const ALocalConverter: ILocalCoordConverter
    ); override;
    procedure StartThreads; override;
  public
    constructor Create(
      const APerfList: IInternalPerformanceCounterList;
      const AAppStartedNotifier: INotifierOneOperation;
      const AAppClosingNotifier: INotifierOneOperation;
      AParentMap: TImage32;
      const AViewPortState: IViewPortState;
      const AConfig: ITileGridConfig
    );
  end;

implementation

uses
  i_CoordConverter,
  u_ListenerByEvent,
  u_GeoFun;

{ TMapLayerTileGrid }

constructor TMapLayerTileGrid.Create(
  const APerfList: IInternalPerformanceCounterList;
  const AAppStartedNotifier: INotifierOneOperation;
  const AAppClosingNotifier: INotifierOneOperation;
  AParentMap: TImage32;
  const AViewPortState: IViewPortState;
  const AConfig: ITileGridConfig
);
begin
  inherited Create(
    APerfList,
    AAppStartedNotifier,
    AAppClosingNotifier,
    AParentMap,
    AViewPortState
  );
  FConfig := AConfig;

  LinksList.Add(
    TNotifyNoMmgEventListener.Create(Self.OnConfigChange),
    FConfig.GetChangeNotifier
  );
end;

procedure TMapLayerTileGrid.OnConfigChange;
begin
  ViewUpdateLock;
  try
    SetVisible(FConfig.Visible);
    SetNeedRedraw;
  finally
    ViewUpdateUnlock;
  end;
end;

procedure TMapLayerTileGrid.PaintLayer(
  ABuffer: TBitmap32;
  const ALocalConverter: ILocalCoordConverter
);
var
  i, j: integer;
  VVisible: Boolean;
  VColor: TColor32;
  VLoadedRect: TDoubleRect;
  VLoadedRelativeRect: TDoubleRect;
  VCurrentZoom: Byte;
  VTilesRect: TRect;
  VTileRelativeRect: TDoubleRect;
  VTileRect: TRect;
  VTileScreenRect: TRect;
  VGridZoom: Byte;
  VTilesLineRect: TRect;
  VGeoConvert: ICoordConverter;
  VLocalRect: TRect;
begin
  inherited;
  VGeoConvert := ALocalConverter.GetGeoConverter;
  VCurrentZoom := ALocalConverter.GetZoom;

  FConfig.LockRead;
  try
    VVisible := FConfig.Visible;
    VColor := FConfig.GridColor;
    if FConfig.UseRelativeZoom then begin
      VGridZoom := VCurrentZoom + FConfig.Zoom;
    end else begin
      VGridZoom := FConfig.Zoom;
    end;
  finally
    FConfig.UnlockRead;
  end;

  if VVisible then begin
    if VGeoConvert.CheckZoom(VGridZoom) then begin
      VVisible := (VGridZoom >= VCurrentZoom - 2) and (VGridZoom <= VCurrentZoom + 5);
    end else begin
      VVisible := False;
    end;
  end;
  if VVisible then begin
    VLocalRect := ALocalConverter.GetLocalRect;
    VLoadedRect := ALocalConverter.LocalRect2MapRectFloat(VLocalRect);
    VGeoConvert.CheckPixelRectFloat(VLoadedRect, VCurrentZoom);

    VLoadedRelativeRect := VGeoConvert.PixelRectFloat2RelativeRect(VLoadedRect, VCurrentZoom);
    VTilesRect := VGeoConvert.RelativeRect2TileRect(VLoadedRelativeRect, VGridZoom);

    VTilesLineRect.Left := VTilesRect.Left;
    VTilesLineRect.Right := VTilesRect.Right;
    for i := VTilesRect.Top to VTilesRect.Bottom do begin
      VTilesLineRect.Top := i;
      VTilesLineRect.Bottom := i;

      VTileRelativeRect := VGeoConvert.TileRect2RelativeRect(VTilesLineRect, VGridZoom);
      VTileRect :=
        RectFromDoubleRect(
          VGeoConvert.RelativeRect2PixelRectFloat(VTileRelativeRect, VCurrentZoom),
          rrToTopLeft
        );
      VTileScreenRect := ALocalConverter.MapRect2LocalRect(VTileRect);

      VTileScreenRect.Left := VLocalRect.Left;
      VTileScreenRect.Right := VLocalRect.Right;

      if VTileScreenRect.Top < VLocalRect.Top then begin
        VTileScreenRect.Top := VLocalRect.Top;
        VTileScreenRect.Bottom := VTileScreenRect.Top;
      end;

      if VTileScreenRect.Top > VLocalRect.Bottom then begin
        VTileScreenRect.Top := VLocalRect.Bottom;
        VTileScreenRect.Bottom := VTileScreenRect.Top;
      end;

      ABuffer.LineTS(VTileScreenRect.Left, VTileScreenRect.Top,
        VTileScreenRect.Right, VTileScreenRect.Top, VColor);
    end;

    VTilesLineRect.Top := VTilesRect.Top;
    VTilesLineRect.Bottom := VTilesRect.Bottom;
    for j := VTilesRect.Left to VTilesRect.Right do begin
      VTilesLineRect.Left := j;
      VTilesLineRect.Right := j;

      VTileRelativeRect := VGeoConvert.TileRect2RelativeRect(VTilesLineRect, VGridZoom);
      VTileRect :=
        RectFromDoubleRect(
          VGeoConvert.RelativeRect2PixelRectFloat(VTileRelativeRect, VCurrentZoom),
          rrToTopLeft
        );
      VTileScreenRect := ALocalConverter.MapRect2LocalRect(VTileRect);

      VTileScreenRect.Top := VLocalRect.Top;
      VTileScreenRect.Bottom := VLocalRect.Bottom;

      if VTileScreenRect.Left < VLocalRect.Left then begin
        VTileScreenRect.Left := VLocalRect.Left;
        VTileScreenRect.Right := VTileScreenRect.Left;
      end;

      if VTileScreenRect.Left > VLocalRect.Right then begin
        VTileScreenRect.Left := VLocalRect.Right;
        VTileScreenRect.Right := VTileScreenRect.Left;
      end;

      ABuffer.LineTS(VTileScreenRect.Left, VTileScreenRect.Top,
        VTileScreenRect.Left, VTileScreenRect.Bottom, VColor);
    end;
  end;
end;

procedure TMapLayerTileGrid.StartThreads;
begin
  inherited;
  OnConfigChange;
end;

end.
