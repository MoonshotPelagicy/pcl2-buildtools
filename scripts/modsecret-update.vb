#Region "更新"

    Private Const UpdateApiUrl As String = "https://api.github.com/repos/MoonshotPelagicy/pcl2-buildtools/releases/latest"
    Private IsUpdating As Boolean = False
    Friend IsUpdateWaitingRestart As Boolean = False

    Private Function GetUpdateVersion() As System.Version
        If ServerConfig Is Nothing OrElse ServerConfig("tag_name") Is Nothing Then Return Nothing
        Dim TagName As String = ServerConfig("tag_name").ToString
        If TagName.StartsWith("pcl-", StringComparison.OrdinalIgnoreCase) Then TagName = TagName.Substring(4)
        If TagName.EndsWith("-patched", StringComparison.OrdinalIgnoreCase) Then TagName = TagName.Substring(0, TagName.Length - 8)
        Return New System.Version(TagName)
    End Function

    Private Function GetUpdateDownloadUrl() As String
        If ServerConfig Is Nothing OrElse ServerConfig("assets") Is Nothing Then Return Nothing
        For Each AssetToken As JToken In ServerConfig("assets")
            Dim Asset = TryCast(AssetToken, JObject)
            If Asset Is Nothing OrElse Asset("name") Is Nothing OrElse Asset("browser_download_url") Is Nothing Then Continue For
            If Asset("name").ToString.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) Then Return Asset("browser_download_url").ToString
        Next
        Return Nothing
    End Function

    Friend Sub UpdateCheckByButton()
        If IsUpdating Then
            Hint("正在检查更新，请稍候！")
            Return
        End If
        IsUpdating = True
        RunInNewThread(
        Sub()
            Try
                ServerLoader.WaitForExit(Input:=0, IsForceRestart:=True)
                If ServerLoader.State = LoadState.Failed OrElse ServerConfig Is Nothing Then Throw New Exception("无法获取 GitHub Release 信息")
                Dim LatestVersion = GetUpdateVersion()
                If LatestVersion Is Nothing Then Throw New Exception("GitHub Release 标签格式无法识别")
                Dim CurrentVersion = New System.Version(VersionBaseName)
                If LatestVersion.CompareTo(CurrentVersion) <= 0 Then
                    Hint($"已经是最新正式版 {VersionBaseName}，不需要更新啦，可以直接使用！", HintType.Green)
                ElseIf MyMsgBox($"发现 PCL 新版本 {LatestVersion}，是否立即下载？", "发现更新！", "更新！冲！", "取消") = 1 Then
                    UpdateStart(False)
                End If
            Catch ex As Exception
                Logger.Error(ex, "检查 PCL 更新失败")
                Hint("检查更新失败，请稍后重试。", HintType.Red)
            Finally
                IsUpdating = False
            End Try
        End Sub, "UpdateCheckByButton", ThreadPriority.BelowNormal)
    End Sub

    Private Sub UpdateStart(Silent As Boolean)
        Try
            Dim DownloadUrl = GetUpdateDownloadUrl()
            If String.IsNullOrWhiteSpace(DownloadUrl) Then Throw New Exception("最新 Release 没有可用的 EXE 附件")
            If Not Silent Then Hint("PCL 正在下载更新，更新结束时将自动重启，请稍候！")

            Dim DownloadPath = PathTemp & "Cache\PCLUpdate.exe"
            Dim UpdaterPath = Paths.Base & "PCL\Plain Craft Launcher 2.exe"
            FileUtils.Delete(DownloadPath)
            DirectoryUtils.Create(Paths.Base & "PCL\")
            ModNet.NetDownloadByLoader(DownloadUrl, DownloadPath, Check:=New FileChecker With {.MinSize = 1024 * 1024})
            FileUtils.Delete(UpdaterPath)
            FileUtils.Copy(DownloadPath, UpdaterPath)
            FileUtils.Delete(DownloadPath)

            If Silent Then
                IsUpdateWaitingRestart = True
            Else
                UpdateRestart(True)
            End If
        Catch ex As Exception
            Logger.Error(ex, "下载 PCL 更新失败")
            IsUpdating = False
            If Not Silent Then Hint("下载更新失败，请稍后重试。", HintType.Red)
        End Try
    End Sub

    Public Sub UpdateRestart(TriggerRestartAndByEnd As Boolean)
        Try
            IsUpdateWaitingRestart = False
            Dim UpdaterPath = Paths.Base & "PCL\Plain Craft Launcher 2.exe"
            If Not FileUtils.Exists(UpdaterPath) Then Throw New FileNotFoundException("找不到更新程序", UpdaterPath)
            Dim Arguments = $"--update {Process.GetCurrentProcess.Id} ""{ModBase.PathExe}"" ""{ModBase.PathExe}"" {TriggerRestartAndByEnd}"
            StartProcess(New ProcessStartInfo(UpdaterPath) With {
                .WindowStyle = ProcessWindowStyle.Hidden,
                .CreateNoWindow = True,
                .Arguments = Arguments
            })
            If TriggerRestartAndByEnd Then ModMain.FrmMain.EndProgram(SendWarning:=False)
        Catch ex As Exception
            Logger.Error(ex, "启动 PCL 更新程序失败")
            Hint("更新程序启动失败，请手动重新打开 PCL。", HintType.Red)
        End Try
    End Sub

    Public Sub UpdateReplace(ProcessId As Integer, OldFileName As String, NewFileName As String, TriggerRestart As Boolean)
        Try
            Try
                Process.GetProcessById(ProcessId).Kill()
            Catch
            End Try

            Dim OldPath = If(Path.IsPathRooted(OldFileName), OldFileName, Paths.Base & OldFileName)
            Dim NewPath = If(Path.IsPathRooted(NewFileName), NewFileName, Paths.Base & NewFileName)
            Dim LastError As Exception = Nothing
            For Retry As Integer = 0 To 4
                Try
                    FileUtils.Delete(OldPath)
                    If NewPath <> OldPath Then FileUtils.Delete(NewPath)
                    If Not FileUtils.Exists(OldPath) AndAlso Not FileUtils.Exists(NewPath) Then Exit For
                Catch ex As Exception
                    LastError = ex
                End Try
                Thread.Sleep(500)
            Next
            If FileUtils.Exists(OldPath) OrElse FileUtils.Exists(NewPath) Then Throw If(LastError, New IOException("无法删除旧版 PCL 文件"))

            FileUtils.Copy(ModBase.PathExe, NewPath)
            If TriggerRestart Then StartProcess(NewPath)
        Catch ex As Exception
            Logger.Error(ex, "替换 PCL 文件失败")
            MsgBox("PCL 更新失败，请手动用更新文件替换原程序。" & vbCrLf & ex.Message, MsgBoxStyle.Critical, "更新失败")
        End Try
    End Sub

    ''' <summary>
    ''' 下载当前 GitHub Release 的 PCL，用于整合包导出。
    ''' </summary>
    Friend Sub DownloadLatestPCL(Optional LoaderToSyncProgress As LoaderBase = Nothing)
        If ServerConfig Is Nothing Then
            ServerLoader.WaitForExit(Input:=0, LoaderToSyncProgress:=LoaderToSyncProgress, IsForceRestart:=True)
        End If
        Dim DownloadUrl = GetUpdateDownloadUrl()
        If String.IsNullOrWhiteSpace(DownloadUrl) Then Throw New Exception("最新 Release 没有可用的 EXE 附件")
        ModNet.NetDownloadByLoader(DownloadUrl, PathTemp & "Latest.exe", LoaderToSyncProgress, New FileChecker With {.MinSize = 1024 * 1024})
    End Sub

#End Region

#Region "联网配置"

    ''' <summary>
    ''' GitHub Releases API 返回的最新 PCL Release 信息。
    ''' </summary>
    Public ServerConfig As JObject

    Public ServerLoader As New LoaderTask(Of Integer, Integer)("PCL 更新信息", Sub(Loader)
        Dim ConfigText = ModNet.NetRequestByClientRetry(UpdateApiUrl, RequireJson:=True)
        ServerConfig = JObject.Parse(ConfigText)
    End Sub, Priority:=ThreadPriority.BelowNormal) With
        {.ReloadTimeout = 1000 * 60 * 60}

#End Region
