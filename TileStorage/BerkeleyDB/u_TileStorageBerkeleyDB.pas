{******************************************************************************}
{* SAS.Planet (SAS.�������)                                                   *}
{* Copyright (C) 2007-2012, SAS.Planet development team.                      *}
{* This program is free software: you can redistribute it and/or modify       *}
{* it under the terms of the GNU General Public License as published by       *}
{* the Free Software Foundation, either version 3 of the License, or          *}
{* (at your option) any later version.                                        *}
{*                                                                            *}
{* This program is distributed in the hope that it will be useful,            *}
{* but WITHOUT ANY WARRANTY; without even the implied warranty of             *}
{* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *}
{* GNU General Public License for more details.                               *}
{*                                                                            *}
{* You should have received a copy of the GNU General Public License          *}
{* along with this program.  If not, see <http://www.gnu.org/licenses/>.      *}
{*                                                                            *}
{* http://sasgis.ru                                                           *}
{* az@sasgis.ru                                                               *}
{******************************************************************************}

unit u_TileStorageBerkeleyDB;

interface

uses
  Windows,
  SysUtils,
  i_BinaryData,
  i_MapVersionInfo,
  i_ContentTypeInfo,
  i_TileInfoBasic,
  i_BasicMemCache,
  i_ContentTypeManager,
  i_CoordConverter,
  i_TileStorage,
  i_MapVersionConfig,
  i_NotifierTime,
  i_ListenerTime,
  i_TileFileNameGenerator,
  i_GlobalBerkeleyDBHelper,
  i_TileInfoBasicMemCache,
  i_TileStorageBerkeleyDBHelper,
  i_TileStorageBerkeleyDBConfigStatic,
  u_TileStorageAbstract;

type
  TTileStorageBerkeleyDB = class(TTileStorageAbstract, IBasicMemCache)
  private
    FGlobalBerkeleyDBHelper: IGlobalBerkeleyDBHelper;
    FStorageHelper: ITileStorageBerkeleyDBHelper;
    FStorageHelperLock: IReadWriteSync;
    FMainContentType: IContentTypeInfoBasic;
    FContentTypeManager: IContentTypeManager;
    FTileNotExistsTileInfo: ITileInfoBasic;
    FGCNotifier: INotifierTime;
    FSyncCallListener: IListenerTimeWithUsedFlag;
    FSyncCallLock: IReadWriteSync;
    FTileInfoMemCache: ITileInfoBasicMemCache;
    FFileNameGenerator: ITileFileNameGenerator;
    FVersioned: Boolean;
    FCommitsCountToSync: Integer;
    FStorageConfig: ITileStorageBerkeleyDBConfigStatic;
    procedure OnSyncCall;
    procedure OnCommitSync;
    function GetStorageHelper: ITileStorageBerkeleyDBHelper;
    function GetStorageFileExtention(const AIsForTneStore: Boolean = False): string;
  protected
    function GetIsFileCache: Boolean; override;
    function GetIsCanSaveMultiVersionTiles: Boolean; override;

    function GetTileFileName(
      const AXY: TPoint;
      const AZoom: Byte;
      const AVersionInfo: IMapVersionInfo
    ): string; override;

    function GetTileInfo(
      const AXY: TPoint;
      const AZoom: Byte;
      const AVersionInfo: IMapVersionInfo;
      const AMode: TGetTileInfoMode
    ): ITileInfoBasic; override;

    function GetTileRectInfo(
      const ARect: TRect;
      const AZoom: Byte;
      const AVersionInfo: IMapVersionInfo
    ): ITileRectInfo; override;

    function DeleteTile(
      const AXY: TPoint;
      const AZoom: Byte;
      const AVersionInfo: IMapVersionInfo
    ): Boolean; override;

    procedure SaveTile(
      const AXY: TPoint;
      const AZoom: Byte;
      const AVersionInfo: IMapVersionInfo;
      const ALoadDate: TDateTime;
      const AContentType: IContentTypeInfoBasic;
      const AData: IBinaryData
    ); override;

    procedure SaveTNE(
      const AXY: TPoint;
      const AZoom: Byte;
      const AVersionInfo: IMapVersionInfo;
      const ALoadDate: TDateTime
    ); override;

    function GetListOfTileVersions(
      const AXY: TPoint;
      const AZoom: byte;
      const AVersionInfo: IMapVersionInfo
    ): IMapVersionListStatic; override;

    function ScanTiles(
      const AIgnoreTNE: Boolean;
      const AIgnoreMultiVersionTiles: Boolean
    ): IEnumTileInfo; override;
  private
    { IBasicMemCache }
    procedure ClearMemCache;
    procedure IBasicMemCache.Clear = ClearMemCache;
  public
    constructor Create(
      const AGlobalBerkeleyDBHelper: IGlobalBerkeleyDBHelper;
      const AGeoConverter: ICoordConverter;
      const AStoragePath: string;
      const AIsVersioned: Boolean;
      const AGCNotifier: INotifierTime;
      const ATileInfoMemCache: ITileInfoBasicMemCache;
      const AContentTypeManager: IContentTypeManager;
      const AMapVersionFactory: IMapVersionFactory;
      const AMainContentType: IContentTypeInfoBasic
    );
    destructor Destroy; override;
  end;

implementation

uses
  WideStrings,
  t_CommonTypes,
  i_TileIterator,
  i_FileNameIterator,
  i_TileFileNameParser,
  u_ListenerTime,
  u_TileRectInfoShort,
  u_TileFileNameBerkeleyDB,
  u_TileIteratorByRect,
  u_TileStorageTypeAbilities,
  u_FileNameIteratorFolderWithSubfolders,
  u_FoldersIteratorRecursiveByLevels,
  u_FileNameIteratorInFolderByMaskList,
  u_TileInfoBasic,
  u_Synchronizer,
  u_GlobalBerkeleyDBHelper,
  u_TileStorageBerkeleyDBHelper,
  u_TileStorageBerkeleyDBConfigStatic,
  u_EnumTileInfoByBerkeleyDB;

const
  cStorageFileExt = '.sdb';
  cTneStorageFileExt = '.tne';
  cVersionedStorageFileExt = '.sdbv';
  cVersionedTneStorageFileExt = '.tnev';

{ TTileStorageBerkeleyDB }

constructor TTileStorageBerkeleyDB.Create(
  const AGlobalBerkeleyDBHelper: IGlobalBerkeleyDBHelper;
  const AGeoConverter: ICoordConverter;
  const AStoragePath: string;
  const AIsVersioned: Boolean;
  const AGCNotifier: INotifierTime;
  const ATileInfoMemCache: ITileInfoBasicMemCache;
  const AContentTypeManager: IContentTypeManager;
  const AMapVersionFactory: IMapVersionFactory;
  const AMainContentType: IContentTypeInfoBasic
);
begin
  Assert(AGlobalBerkeleyDBHelper <> nil);

  FStorageConfig := TTileStorageBerkeleyDBConfigStatic.Create(AStoragePath);    // ToDo: get StorageConfig as param

  inherited Create(
    TTileStorageTypeAbilitiesBerkeleyDB.Create(FStorageConfig.IsReadOnly),
    AMapVersionFactory,
    AGeoConverter,
    AStoragePath
  );

  FGlobalBerkeleyDBHelper := AGlobalBerkeleyDBHelper;
  FContentTypeManager := AContentTypeManager;
  FMainContentType := AMainContentType;
  FTileInfoMemCache := ATileInfoMemCache;
  FGCNotifier := AGCNotifier;
  FTileNotExistsTileInfo := TTileInfoBasicNotExists.Create(0, nil);

  FFileNameGenerator := TTileFileNameBerkeleyDB.Create as ITileFileNameGenerator;

  FVersioned := AIsVersioned;

  FSyncCallListener := TListenerTTLCheck.Create(
    Self.OnSyncCall,
    FStorageConfig.SyncInterval
  );

  if Assigned(FGCNotifier) and Assigned(FSyncCallListener) then begin
    FGCNotifier.Add(FSyncCallListener);
  end;

  FStorageHelper := nil;
  FStorageHelperLock := MakeSyncRW_Var(Self, False);

  FCommitsCountToSync := FStorageConfig.CommitsCountToSync;
  FSyncCallLock := MakeSyncRW_Std(Self, False);
end;

destructor TTileStorageBerkeleyDB.Destroy;
begin
  if Assigned(FGCNotifier) and Assigned(FSyncCallListener) then begin
    FGCNotifier.Remove(FSyncCallListener);
  end;
  FGCNotifier := nil;
  FSyncCallListener := nil;
  FStorageHelper := nil;
  FGlobalBerkeleyDBHelper := nil;
  FTileInfoMemCache := nil;
  FMainContentType := nil;
  FContentTypeManager := nil;
  FTileNotExistsTileInfo := nil;
  FStorageConfig := nil;
  inherited;
end;

procedure TTileStorageBerkeleyDB.OnSyncCall;
var
  VHelper: ITileStorageBerkeleyDBHelper;
  VHotDbCount: Integer;
begin
  try
    FStorageHelperLock.BeginRead;
    try
      VHelper := FStorageHelper;
    finally
      FStorageHelperLock.EndRead;
    end;

    if Assigned(VHelper) then begin
      FSyncCallLock.BeginWrite;
      try
        VHelper.Sync(VHotDbCount);
        VHelper := nil;

        if VHotDbCount <= 0 then begin
          FStorageHelperLock.BeginWrite;
          try
            if Assigned(FStorageHelper) and (FStorageHelper.RefCount = 1) then begin
              FStorageHelper := nil;
            end;
          finally
            FStorageHelperLock.EndWrite;
          end;
        end else begin
          FSyncCallListener.CheckUseTimeUpdated;
        end;

        FCommitsCountToSync := FStorageConfig.CommitsCountToSync;
      finally
        FSyncCallLock.EndWrite;
      end;
    end;
  except
    on E: Exception do begin
      if Assigned(FGlobalBerkeleyDBHelper) then begin
        FGlobalBerkeleyDBHelper.LogException(E.ClassName + ': ' + E.Message);
      end;
      TryShowLastExceptionData;
      raise;
    end;
  end;
end;

procedure TTileStorageBerkeleyDB.OnCommitSync;
var
  VDoSyncCall: Boolean;
begin
  FSyncCallLock.BeginWrite;
  try
    Dec(FCommitsCountToSync);
    VDoSyncCall := (FCommitsCountToSync <= 0);
    if VDoSyncCall then begin
      FCommitsCountToSync := FStorageConfig.CommitsCountToSync;
    end;
  finally
    FSyncCallLock.EndWrite;
  end;

  if VDoSyncCall then begin
    Self.OnSyncCall;
  end;
end;

function TTileStorageBerkeleyDB.GetIsFileCache: Boolean;
begin
  Result := False;
end;

function TTileStorageBerkeleyDB.GetIsCanSaveMultiVersionTiles: Boolean;
begin
  Result := FVersioned;
end;

function TTileStorageBerkeleyDB.GetStorageFileExtention(const AIsForTneStore: Boolean = False): string;
begin
  if not AIsForTneStore then begin
    if FVersioned then begin
      Result := cVersionedStorageFileExt;
    end else begin
      Result := cStorageFileExt;
    end;
  end else begin
    if FVersioned then begin
      Result := cVersionedTneStorageFileExt;
    end else begin
      Result := cTneStorageFileExt;
    end;
  end;
end;

function TTileStorageBerkeleyDB.GetTileFileName(
  const AXY: TPoint;
  const AZoom: Byte;
  const AVersionInfo: IMapVersionInfo
): string;
begin
  Result :=
    StoragePath +
    FFileNameGenerator.GetTileFileName(AXY, AZoom) +
    GetStorageFileExtention;
end;

function TTileStorageBerkeleyDB.GetTileInfo(
  const AXY: TPoint;
  const AZoom: Byte;
  const AVersionInfo: IMapVersionInfo;
  const AMode: TGetTileInfoMode
): ITileInfoBasic;
var
  VPath: string;
  VResult: Boolean;
  VTileBinaryData: IBinaryData;
  VTileVersion: WideString;
  VTileContentType: WideString;
  VTileDate: TDateTime;
  VTileSize: Integer;
  VList: IMapVersionListStatic;
  VHelper: ITileStorageBerkeleyDBHelper;
begin
  try
    if Assigned(FTileInfoMemCache) then begin
      Result := FTileInfoMemCache.Get(AXY, AZoom, AVersionInfo, AMode, True);
      if Result <> nil then begin
        Exit;
      end;
    end;
    Result := FTileNotExistsTileInfo;
    if GetState.GetStatic.ReadAccess <> asDisabled then begin

      VPath :=
        StoragePath +
        FFileNameGenerator.GetTileFileName(AXY, AZoom) +
        GetStorageFileExtention;

      VResult := False;

      if FileExists(VPath) then begin
        VHelper := GetStorageHelper; 
        if AMode = gtimWithoutData then begin
          VResult :=
            VHelper.LoadTileInfo(
              VPath,
              AXY,
              AZoom,
              AVersionInfo,
              True, // will get single tile info
              VList,
              VTileVersion,
              VTileContentType,
              VTileSize,
              VTileDate
            );
          if VResult then begin
            Result :=
              TTileInfoBasicExists.Create(
                VTileDate,
                VTileSize,
                MapVersionFactory.CreateByStoreString(VTileVersion),
                FContentTypeManager.GetInfo(VTileContentType)
              );
          end;
        end else begin
          VResult :=
            VHelper.LoadTile(
              VPath,
              AXY,
              AZoom,
              AVersionInfo,
              VTileBinaryData,
              VTileVersion,
              VTileContentType,
              VTileDate
            );
          if VResult then begin
            Result :=
              TTileInfoBasicExistsWithTile.Create(
                VTileDate,
                VTileBinaryData,
                MapVersionFactory.CreateByStoreString(VTileVersion),
                FContentTypeManager.GetInfo(VTileContentType)
              );
          end;
        end;
      end;

      if not VResult then begin
        VPath := ChangeFileExt(VPath, GetStorageFileExtention(True));
        if FileExists(VPath) then begin
          if not Assigned(VHelper) then begin
            VHelper := GetStorageHelper;
          end;
          VResult := VHelper.IsTNEFound(
            VPath,
            AXY,
            AZoom,
            AVersionInfo,
            VTileDate
          );
          if VResult then begin
            Result := TTileInfoBasicTNE.Create(VTileDate, AVersionInfo);
          end;
        end;
      end;

      if not VResult then begin
        Result := TTileInfoBasicNotExists.Create(0, AVersionInfo);
      end;
    end;

    if Assigned(FTileInfoMemCache) then begin
      FTileInfoMemCache.Add(AXY, AZoom, AVersionInfo, Result);
    end;
  except
    on E: Exception do begin
      if Assigned(FGlobalBerkeleyDBHelper) then begin
        FGlobalBerkeleyDBHelper.LogException(E.ClassName + ': ' + E.Message);
      end;
      TryShowLastExceptionData;
      raise;
    end;
  end;
end;

function TTileStorageBerkeleyDB.GetListOfTileVersions(
  const AXY: TPoint;
  const AZoom: byte;
  const AVersionInfo: IMapVersionInfo
): IMapVersionListStatic;
var
  VPath: string;
  VResult: Boolean;
  VTileVersion: WideString;
  VTileContentType: WideString;
  VTileDate: TDateTime;
  VTileSize: Integer;
  VList: IMapVersionListStatic;
  VHelper: ITileStorageBerkeleyDBHelper;
begin
  Result := nil;
  try
    if GetState.GetStatic.ReadAccess <> asDisabled then begin
      VPath := StoragePath + FFileNameGenerator.GetTileFileName(AXY, AZoom) + GetStorageFileExtention;
      if FileExists(VPath) then begin
        VHelper := GetStorageHelper;
        VResult :=
          VHelper.LoadTileInfo(
            VPath,
            AXY,
            AZoom,
            AVersionInfo,
            False, // will get multi-versions tile info
            VList,
            VTileVersion,
            VTileContentType,
            VTileSize,
            VTileDate
          );
        if VResult then begin
          Result := VList;
        end;
      end;
    end;
  except
    on E: Exception do begin
      if Assigned(FGlobalBerkeleyDBHelper) then begin
        FGlobalBerkeleyDBHelper.LogException(E.ClassName + ': ' + E.Message);
      end;
      TryShowLastExceptionData;
      raise;
    end;
  end;
end;

function TTileStorageBerkeleyDB.GetTileRectInfo(
  const ARect: TRect;
  const AZoom: Byte;
  const AVersionInfo: IMapVersionInfo
): ITileRectInfo;

type
  TInfo = record
    Name: string;
    PrevName: string;
    Exists: Boolean;
    PrevExists: Boolean;
  end;

  procedure ClearInfo(var AInfo: TInfo);
  begin
    AInfo.Name := '';
    AInfo.PrevName := '';
    AInfo.Exists := False;
    AInfo.PrevExists := False;
  end;

var
  VRect: TRect;
  VZoom: Byte;
  VCount: TPoint;
  VItems: TArrayOfTileInfoShortInternal;
  VIndex: Integer;
  VTile: TPoint;
  VIterator: ITileIterator;
  VFolderInfo: TInfo;
  VFileInfo: TInfo;
  VTneFileInfo: TInfo;
  VTileExists: Boolean;
  VTileBinaryData: IBinaryData;
  VTileVersion: WideString;
  VTileContentType: WideString;
  VTileDate: TDateTime;
  VHelper: ITileStorageBerkeleyDBHelper;
begin
  Result := nil;
  try
    if GetState.GetStatic.ReadAccess <> asDisabled then begin
      VHelper := nil;
      VRect := ARect;
      VZoom := AZoom;
      GeoConverter.CheckTileRect(VRect, VZoom);
      VCount.X := VRect.Right - VRect.Left;
      VCount.Y := VRect.Bottom - VRect.Top;
      if (VCount.X > 0) and (VCount.Y > 0) and (VCount.X <= 2048) and (VCount.Y <= 2048) then begin
        SetLength(VItems, VCount.X * VCount.Y);
        ClearInfo(VFolderInfo);
        ClearInfo(VFileInfo);
        ClearInfo(VTneFileInfo);
        VIterator := TTileIteratorByRect.Create(VRect);
        while VIterator.Next(VTile) do begin
          VIndex := TTileRectInfoShort.TileInRectToIndex(VTile, VRect);
          Assert(VIndex >=0);
          if VIndex >= 0 then begin
            VFileInfo.Name :=
              StoragePath +
              FFileNameGenerator.GetTileFileName(VTile, VZoom) +
              GetStorageFileExtention;
            VTneFileInfo.Name := ChangeFileExt(VFileInfo.Name, GetStorageFileExtention(True));
            VFolderInfo.Name := ExtractFilePath(VFileInfo.Name);

            if VFolderInfo.Name = VFolderInfo.PrevName then begin
              VFolderInfo.Exists := VFolderInfo.PrevExists;
            end else begin
              VFolderInfo.Exists := DirectoryExists(VFolderInfo.Name);
              VFolderInfo.PrevName := VFolderInfo.Name;
              VFolderInfo.PrevExists := VFolderInfo.Exists;
            end;

            if VFileInfo.Name = VFileInfo.PrevName then begin
              VFileInfo.Exists := VFileInfo.PrevExists;
            end else begin
              VFileInfo.Exists := FileExists(VFileInfo.Name);
              VFileInfo.PrevName := VFileInfo.Name;
              VFileInfo.PrevExists := VFileInfo.Exists;
            end;

            if VTneFileInfo.Name = VTneFileInfo.PrevName then begin
              VTneFileInfo.Exists := VTneFileInfo.PrevExists;
            end else begin
              VTneFileInfo.Exists := FileExists(VTneFileInfo.Name);
              VTneFileInfo.PrevName := VTneFileInfo.Name;
              VTneFileInfo.PrevExists := VTneFileInfo.Exists;
            end;

            if (VFolderInfo.Exists and (VFileInfo.Exists or VTneFileInfo.Exists)) then begin
              if not Assigned(VHelper) then begin
                VHelper := GetStorageHelper;
              end;
              VTileExists := VHelper.LoadTile(
                VFileInfo.Name,
                VTile,
                VZoom,
                AVersionInfo,
                VTileBinaryData,
                VTileVersion,
                VTileContentType,
                VTileDate
              );
              if VTileExists then begin
                // tile exists
                VItems[VIndex].FLoadDate := VTileDate;
                VItems[VIndex].FSize := VTileBinaryData.Size;
                VItems[VIndex].FInfoType := titExists;
              end else begin
                VTileExists := VHelper.IsTNEFound(
                  VTneFileInfo.Name,
                  VTile,
                  VZoom,
                  AVersionInfo,
                  VTileDate
                );
                if VTileExists then begin
                  // tne exists
                  VItems[VIndex].FLoadDate := VTileDate;
                  VItems[VIndex].FSize := 0;
                  VItems[VIndex].FInfoType := titTneExists;
                end else begin
                  // neither tile nor tne
                  VItems[VIndex].FLoadDate := 0;
                  VItems[VIndex].FSize := 0;
                  VItems[VIndex].FInfoType := titNotExists;
                end;
              end;
            end else begin
              // neither tile nor tne
              VItems[VIndex].FLoadDate := 0;
              VItems[VIndex].FSize := 0;
              VItems[VIndex].FInfoType := titNotExists;
            end;
          end;
        end;
        Result :=
          TTileRectInfoShort.CreateWithOwn(
            VRect,
            VZoom,
            nil,
            FMainContentType,
            VItems
          );
        VItems := nil;
        if Assigned(VHelper) then begin
          FSyncCallListener.CheckUseTimeUpdated;
        end;
      end;
    end;
  except
    on E: Exception do begin
      if Assigned(FGlobalBerkeleyDBHelper) then begin
        FGlobalBerkeleyDBHelper.LogException(E.ClassName + ': ' + E.Message);
      end;
      TryShowLastExceptionData;
      raise;
    end;
  end;
end;

procedure TTileStorageBerkeleyDB.SaveTile(
  const AXY: TPoint;
  const AZoom: Byte;
  const AVersionInfo: IMapVersionInfo;
  const ALoadDate: TDateTime;
  const AContentType: IContentTypeInfoBasic;
  const AData: IBinaryData
);
var
  VPath: string;
  VResult: Boolean;
  VDoNotifyUpdate: Boolean;
  VTileInfo: ITileInfoBasic;
  VHelper: ITileStorageBerkeleyDBHelper;
begin
  VDoNotifyUpdate := False;
  try
    if GetState.GetStatic.WriteAccess <> asDisabled then begin
      if not FMainContentType.CheckOtherForSaveCompatible(AContentType) then begin
        raise Exception.Create('Bad content type for this tile storage');
      end;
      VPath :=
        StoragePath +
        FFileNameGenerator.GetTileFileName(AXY, AZoom) +
        GetStorageFileExtention;
      if CreateDirIfNotExists(VPath) then begin
        VHelper := GetStorageHelper;
        VResult := VHelper.SaveTile(
          VPath,
          AXY,
          AZoom,
          ALoadDate,
          AVersionInfo,
          AContentType,
          AData,
          False // ToDo: KeepExisting
        );
        if VResult then begin
          VTileInfo :=
            TTileInfoBasicExistsWithTile.Create(
              ALoadDate,
              AData,
              AVersionInfo,
              FMainContentType
            );
          if Assigned(FTileInfoMemCache) then begin
            FTileInfoMemCache.Add(
              AXY,
              AZoom,
              AVersionInfo,
              VTileInfo
            );
          end;
          VDoNotifyUpdate := True;
        end;
      end;
    end;
  except
    on E: Exception do begin
      if Assigned(FGlobalBerkeleyDBHelper) then begin
        FGlobalBerkeleyDBHelper.LogException(E.ClassName + ': ' + E.Message);
      end;
      TryShowLastExceptionData;
      raise;
    end;
  end;

  if VDoNotifyUpdate then begin
    NotifyTileUpdate(AXY, AZoom, AVersionInfo);
    OnCommitSync;
  end;
end;

procedure TTileStorageBerkeleyDB.SaveTNE(
  const AXY: TPoint;
  const AZoom: Byte;
  const AVersionInfo: IMapVersionInfo;
  const ALoadDate: TDateTime
);
var
  VPath: String;
  VResult: Boolean;
  VDoNotifyUpdate: Boolean;
  VHelper: ITileStorageBerkeleyDBHelper;
begin
  VDoNotifyUpdate := False;
  if GetState.GetStatic.WriteAccess <> asDisabled then begin
    DeleteTile(AXY, AZoom, AVersionInfo); // del old tile if exists
    try
      VPath :=
        StoragePath +
        FFileNameGenerator.GetTileFileName(AXY, AZoom) +
        GetStorageFileExtention(True);
      if CreateDirIfNotExists(VPath) then begin
        VHelper := GetStorageHelper;
        VResult := VHelper.SaveTile(
          VPath,
          AXY,
          AZoom,
          ALoadDate,
          AVersionInfo,
          nil,
          nil,
          False // ToDo: KeepExisting
        );
        if VResult then begin
          if Assigned(FTileInfoMemCache) then begin
            FTileInfoMemCache.Add(
              AXY,
              AZoom,
              AVersionInfo,
              TTileInfoBasicTNE.Create(ALoadDate, AVersionInfo)
            );
          end;
          VDoNotifyUpdate := True;
        end;
      end;
    except
      on E: Exception do begin
        if Assigned(FGlobalBerkeleyDBHelper) then begin
          FGlobalBerkeleyDBHelper.LogException(E.ClassName + ': ' + E.Message);
        end;
        TryShowLastExceptionData;
        raise;
      end;
    end;
  end;

  if VDoNotifyUpdate then begin
    NotifyTileUpdate(AXY, AZoom, AVersionInfo);
    OnCommitSync;
  end;
end;

function TTileStorageBerkeleyDB.DeleteTile(
  const AXY: TPoint;
  const AZoom: Byte;
  const AVersionInfo: IMapVersionInfo
): Boolean;
var
  VPath: string;
  VDoNotifyUpdate: Boolean;
  VHelper: ITileStorageBerkeleyDBHelper;
begin
  Result := False;
  VDoNotifyUpdate := False;
  try
    if GetState.GetStatic.DeleteAccess <> asDisabled then begin
      try
        VPath :=
          StoragePath +
          FFileNameGenerator.GetTileFileName(AXY, AZoom) +
          GetStorageFileExtention;
        if FileExists(VPath) then begin
          VHelper := GetStorageHelper;
          Result := VHelper.DeleteTile(
            VPath,
            AXY,
            AZoom,
            AVersionInfo
          );
        end;
        if not Result then begin
          VPath :=
            StoragePath +
            FFileNameGenerator.GetTileFileName(AXY, AZoom) +
            GetStorageFileExtention(True);
          if FileExists(VPath) then begin
            if not Assigned(VHelper) then begin
              VHelper := GetStorageHelper;
            end;
            Result := VHelper.DeleteTile(
              VPath,
              AXY,
              AZoom,
              AVersionInfo
            );
          end;
        end;
      except
        Result := False;
      end;
      if Result then begin
        if Assigned(FTileInfoMemCache) then begin
          FTileInfoMemCache.Add(
            AXY,
            AZoom,
            AVersionInfo,
            TTileInfoBasicNotExists.Create(0, AVersionInfo)
          );
        end;
        VDoNotifyUpdate := True;
      end;
    end;
  except
    on E: Exception do begin
      if Assigned(FGlobalBerkeleyDBHelper) then begin
        FGlobalBerkeleyDBHelper.LogException(E.ClassName + ': ' + E.Message);
      end;
      TryShowLastExceptionData;
      raise;
    end;
  end;

  if VDoNotifyUpdate then begin
    NotifyTileUpdate(AXY, AZoom, AVersionInfo);
    OnCommitSync;
  end;
end;

function TTileStorageBerkeleyDB.ScanTiles(
  const AIgnoreTNE: Boolean;
  const AIgnoreMultiVersionTiles: Boolean
): IEnumTileInfo;
const
  cMaxFolderDepth = 10;
var
  VProcessFileMasks: TWideStringList;
  VFileNameParser: ITileFileNameParser;
  VFilesIterator: IFileNameIterator;
  VFoldersIteratorFactory: IFileNameIteratorFactory;
  VFilesInFolderIteratorFactory: IFileNameIteratorFactory;
  VHelper: ITileStorageBerkeleyDBHelper;
begin
  VProcessFileMasks := TWideStringList.Create;
  try
    VProcessFileMasks.Add('*' + GetStorageFileExtention);
    if not AIgnoreTNE then begin
      VProcessFileMasks.Add('*' + GetStorageFileExtention(True));
    end;

    VFoldersIteratorFactory :=
      TFoldersIteratorRecursiveByLevelsFactory.Create(cMaxFolderDepth);

    VFilesInFolderIteratorFactory :=
      TFileNameIteratorInFolderByMaskListFactory.Create(VProcessFileMasks, True);

    VFilesIterator := TFileNameIteratorFolderWithSubfolders.Create(
      StoragePath,
      '',
      VFoldersIteratorFactory,
      VFilesInFolderIteratorFactory
    );

    VFileNameParser := TTileFileNameBerkeleyDB.Create as ITileFileNameParser;

    VHelper := GetStorageHelper;

    Result :=
      TEnumTileInfoByBerkeleyDB.Create(
        FGlobalBerkeleyDBHelper,
        AIgnoreMultiVersionTiles,
        VFilesIterator,
        VFileNameParser,
        Self.MapVersionFactory,
        (Self as ITileStorage),
        VHelper
      );
  finally
    VProcessFileMasks.Free;
  end;
end;

procedure TTileStorageBerkeleyDB.ClearMemCache;
begin
  if Assigned(FTileInfoMemCache) then begin
    FTileInfoMemCache.Clear;
  end;
end;

function TTileStorageBerkeleyDB.GetStorageHelper: ITileStorageBerkeleyDBHelper;
begin
  FStorageHelperLock.BeginRead;
  try
    Result := FStorageHelper;
  finally
    FStorageHelperLock.EndRead;
  end;

  if not Assigned(Result) then begin
    FStorageHelperLock.BeginWrite;
    try
      if not Assigned(FStorageHelper) then begin    
        FStorageHelper := TTileStorageBerkeleyDBHelper.Create(
          FGlobalBerkeleyDBHelper,
          MapVersionFactory,
          FStorageConfig,
          StoragePath,
          FVersioned,
          GeoConverter.ProjectionEPSG
        );
      end;
      Result := FStorageHelper;
    finally
      FStorageHelperLock.EndWrite;
    end;
  end;

  FSyncCallListener.CheckUseTimeUpdated; 

  Assert(Result <> nil);
end;

end.
