' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/wm/WmMain.bas
' Summary: Standalone Ring 3 Window Manager Service daemon (srv.wm).
'          Manages window hierarchies, focus arbitration, titlebar dragging,
'          resizing, minimization, maximization, and decoupled theme decorations.

Import "../../include/pros.bas"
Import "WindowTheme.bas"

Module WmMain

    ' =========================================================================
    ' 1. Window Manager Protocol & IPC Constants
    ' =========================================================================
    Public Const WM_CMD_REGISTER_TABLE  As UInt32 = 30
    Public Const WM_CMD_CREATE_WINDOW    As UInt32 = 31
    Public Const WM_CMD_DESTROY_WINDOW   As UInt32 = 32
    Public Const WM_CMD_SET_FOCUS        As UInt32 = 22
    Public Const WM_CMD_MOVE_WINDOW      As UInt32 = 23
    Public Const WM_CMD_RESIZE_WINDOW    As UInt32 = 24
    Public Const WM_CMD_MINIMIZE_WINDOW  As UInt32 = 25
    Public Const WM_CMD_MAXIMIZE_WINDOW  As UInt32 = 26
    Public Const WM_CMD_RESTORE_WINDOW   As UInt32 = 27
    Public Const WM_CMD_MOUSE_EVENT      As UInt32 = 33
    Public Const WM_CMD_SET_CURSOR       As UInt32 = 34
    Public Const WM_CMD_WINDOW_DIRTY     As UInt32 = 35

    Public Const WM_RESP_OK              As UInt32 = 200
    Public Const WM_RESP_ERROR           As UInt32 = 201

    Public Const MAX_WINDOWS             As UInt32 = 16

    ' =========================================================================
    ' 2. Window Hierarchy State Structure
    ' =========================================================================
    <Packed>
    Structure WindowItem
        Public Id          As UInt32
        Public OwnerPid    As UInt64
        Public X           As Int32
        Public Y           As Int32
        Public Width         As Int32
        Public Height        As Int32
        Public SurfaceWidth  As Int32
        Public SurfaceHeight As Int32
        Public SavedX        As Int32
        Public SavedY      As Int32
        Public SavedW      As Int32
        Public SavedH      As Int32
        Public Flags       As UInt32
        Public State       As Int32   ' 0=Normal, 1=Minimized, 2=Maximized
        Public Focused     As Boolean
        Public Dragging    As Boolean
        Public Resizing    As Boolean
        Public DragOffsetX As Int32
        Public DragOffsetY As Int32
        Public LastMouseX  As Int32
        Public LastMouseY  As Int32
        Public ShmId       As UInt64  ' Zero-Copy Client Surface SHMID
        Public ClientVaddr As UInt64  ' Virtual mapping address
        Public Title(32)   As Byte
    End Structure

    Private windows(15) As WindowItem
    Private windowCount As UInt32 = 0
    Private focusedWinId As UInt32 = 0

    ' Shared Memory WindowTable pointer (published to srv.compositor)
    Private pWindowTable As Pointer To WindowTable = 0
    Private shmTableId As UInt64 = 0

    ' Mouse tracking state for window arbitration
    Private lastMouseX As Int32 = 0
    Private lastMouseY As Int32 = 0
    Private lastButtons As Byte = 0
    Private lastClickTime As UInt64 = 0
    Private lastClickWinId As UInt32 = 0

    ''
    ' @brief Synchronize internal window tree to shared memory WindowTable.
    ''
    Public Unsafe Sub SyncWindowTable()
        If pWindowTable = 0 Then Exit Sub
        pWindowTable.Revision = pWindowTable.Revision + 1
        pWindowTable.Count = windowCount
        Dim i As UInt32 = 0
        While i < windowCount
            pWindowTable.Windows(i).WinId = windows(i).Id
            pWindowTable.Windows(i).OwnerPid = windows(i).OwnerPid
            pWindowTable.Windows(i).X = windows(i).X
            pWindowTable.Windows(i).Y = windows(i).Y
            pWindowTable.Windows(i).Width = windows(i).Width
            pWindowTable.Windows(i).Height = windows(i).Height
            pWindowTable.Windows(i).SurfaceWidth = windows(i).SurfaceWidth
            pWindowTable.Windows(i).SurfaceHeight = windows(i).SurfaceHeight
            pWindowTable.Windows(i).State = windows(i).State
            pWindowTable.Windows(i).Focused = windows(i).Focused
            pWindowTable.Windows(i).ShmId = windows(i).ShmId
            pWindowTable.Windows(i).ClientVaddr = windows(i).ClientVaddr

            Dim t As UInt32 = 0
            While t < 31 And windows(i).Title(t) <> 0
                pWindowTable.Windows(i).Title(t) = windows(i).Title(t)
                t = t + 1
            Wend
            pWindowTable.Windows(i).Title(t) = 0
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Find window pointer by its identifier.
    ' @param winId Target window identifier.
    ' @return Pointer to WindowItem or 0 if not found.
    ''
    Public Unsafe Function FindWindow(ByVal winId As UInt32) As Pointer To WindowItem
        Dim i As UInt32 = 0
        While i < windowCount
            If windows(i).Id = winId Then
                FindWindow = CPtr(Pointer To WindowItem, AddressOf windows(i))
                Exit Function
            End If
            i = i + 1
        Wend
        FindWindow = 0
    End Function

    ''
    ' @brief Add a new managed window to the desktop hierarchy.
    ''
    Public Unsafe Function AddWindow(ByVal id As UInt32, ByVal ownerPid As UInt64, _
                                     ByVal x As Int32, ByVal y As Int32, _
                                     ByVal w As Int32, ByVal h As Int32, _
                                     ByVal flags As UInt32, ByVal shmId As UInt64, _
                                     ByVal titlePtr As Pointer To Byte) As Pointer To WindowItem
        If windowCount >= MAX_WINDOWS Then
            AddWindow = 0
            Exit Function
        End If

        Dim idx As UInt32 = windowCount
        windows(idx).Id = id
        windows(idx).OwnerPid = ownerPid
        windows(idx).X = x
        windows(idx).Y = y
        Dim clientAreaW As Int32 = w - 4
        If clientAreaW < 1 Then clientAreaW = 1
        Dim clientAreaH As Int32 = (h - 26) - 4
        If clientAreaH < 1 Then clientAreaH = 1

        windows(idx).Width = w
        windows(idx).Height = h
        windows(idx).SurfaceWidth = clientAreaW
        windows(idx).SurfaceHeight = clientAreaH
        windows(idx).SavedX = x
        windows(idx).SavedY = y
        windows(idx).SavedW = w
        windows(idx).SavedH = h
        windows(idx).Flags = flags
        windows(idx).State = WIN_STATE_NORMAL
        windows(idx).Focused = False
        windows(idx).Dragging = False
        windows(idx).Resizing = False
        windows(idx).DragOffsetX = 0
        windows(idx).DragOffsetY = 0
        windows(idx).LastMouseX = 0
        windows(idx).LastMouseY = 0
        windows(idx).ShmId = shmId
        windows(idx).ClientVaddr = 0
        Dim t As UInt32 = 0
        While t < 31 And titlePtr <> 0 And titlePtr(t) <> 0
            windows(idx).Title(t) = titlePtr(t)
            t = t + 1
        Wend
        windows(idx).Title(t) = 0

        windowCount = windowCount + 1
        SyncWindowTable
        AddWindow = CPtr(Pointer To WindowItem, AddressOf windows(idx))
    End Function

    ''
    ' @brief Raise window to the top of the desktop Z-order stack.
    ''
    Public Unsafe Function RaiseWindow(ByVal winId As UInt32) As Boolean
        If windowCount <= 1 Then
            RaiseWindow = True
            Exit Function
        End If

        Dim foundIdx As Int32 = -1
        Dim i As UInt32 = 0
        While i < windowCount
            If windows(i).Id = winId Then
                foundIdx = CType(Int32, i)
                Exit While
            End If
            i = i + 1
        Wend

        If foundIdx < 0 Or foundIdx = CType(Int32, windowCount - 1) Then
            RaiseWindow = (foundIdx >= 0)
            Exit Function
        End If

        ' Shift windows down and place raised window at top
        Dim target As WindowItem = windows(foundIdx)
        Dim s As UInt32 = CType(UInt32, foundIdx)
        While s < (windowCount - 1)
            windows(s) = windows(s + 1)
            s = s + 1
        Wend
        windows(windowCount - 1) = target
        RaiseWindow = True
    End Function

    ''
    ' @brief Set input focus to the specified window and update Z-order.
    ''
    Public Unsafe Function SetFocus(ByVal winId As UInt32) As Boolean
        Dim i As UInt32 = 0
        Dim found As Boolean = False
        While i < windowCount
            If windows(i).Id = winId Then
                windows(i).Focused = True
                focusedWinId = winId
                found = True
            Else
                windows(i).Focused = False
            End If
            i = i + 1
        Wend

        If found Then
            RaiseWindow winId
        End If
        SetFocus = found
    End Function

    ''
    ' @brief Minimize specified window.
    ''
    Public Unsafe Function MinimizeWindow(ByVal winId As UInt32) As Boolean
        Dim pWin As Pointer To WindowItem = FindWindow(winId)
        If pWin = 0 Then
            MinimizeWindow = False
            Exit Function
        End If
        pWin.State = WIN_STATE_MINIMIZED
        pWin.Focused = False
        pWin.Dragging = False
        pWin.Resizing = False
        MinimizeWindow = True
    End Function

    ''
    ' @brief Maximize specified window to desktop dimensions.
    ''
    Public Unsafe Function MaximizeWindow(ByVal winId As UInt32, ByVal screenW As Int32, ByVal screenH As Int32) As Boolean
        Dim pWin As Pointer To WindowItem = FindWindow(winId)
        If pWin = 0 Then
            MaximizeWindow = False
            Exit Function
        End If

        ' Save current floating bounds
        If pWin.State = WIN_STATE_NORMAL Then
            pWin.SavedX = pWin.X
            pWin.SavedY = pWin.Y
            pWin.SavedW = pWin.Width
            pWin.SavedH = pWin.Height
        End If

        pWin.X = 0
        pWin.Y = 26 ' Below system top menu bar
        pWin.Width = screenW
        pWin.Height = screenH - 26
        pWin.State = WIN_STATE_MAXIMIZED
        pWin.Dragging = False
        pWin.Resizing = False
        MaximizeWindow = True
    End Function

    ''
    ' @brief Restore window from minimized or maximized state to floating geometry.
    ''
    Public Unsafe Function RestoreWindow(ByVal winId As UInt32) As Boolean
        Dim pWin As Pointer To WindowItem = FindWindow(winId)
        If pWin = 0 Then
            RestoreWindow = False
            Exit Function
        End If

        pWin.X = pWin.SavedX
        pWin.Y = pWin.SavedY
        pWin.Width = pWin.SavedW
        pWin.Height = pWin.SavedH
        pWin.State = WIN_STATE_NORMAL
        pWin.Dragging = False
        pWin.Resizing = False
        RestoreWindow = True
    End Function

    ''
    ' @brief Close and destroy window item from the managed hierarchy.
    ''
    Public Unsafe Function DestroyWindow(ByVal winId As UInt32) As Boolean
        Dim foundIdx As Int32 = -1
        Dim i As UInt32 = 0
        While i < windowCount
            If windows(i).Id = winId Then
                foundIdx = CType(Int32, i)
                Exit While
            End If
            i = i + 1
        Wend

        If foundIdx < 0 Then
            DestroyWindow = False
            Exit Function
        End If

        Dim s As UInt32 = CType(UInt32, foundIdx)
        While s < (windowCount - 1)
            windows(s) = windows(s + 1)
            s = s + 1
        Wend
        windowCount = windowCount - 1

        If focusedWinId = winId Then
            If windowCount > 0 Then
                SetFocus windows(windowCount - 1).Id
            Else
                focusedWinId = 0
            End If
        End If
        DestroyWindow = True
    End Function

    ''
    ' @brief Initialize default system desktop windows.
    ''
    Private Unsafe Sub InitWindows()
        windowCount = 0
        SyncWindowTable
    End Sub

    ''
    ' @brief Process incoming mouse interaction across desktop windows.
    ' @param mouseX Current mouse X screen coordinate.
    ' @param mouseY Current mouse Y screen coordinate.
    ' @param buttons Current mouse buttons bitmask.
    ' @param screenW Screen width in pixels.
    ' @param screenH Screen height in pixels.
    ' @return True if window focus, geometry, or state changed; False if pure mouse motion.
    ''
    Public Unsafe Function ProcessMouseInteraction(ByVal mouseX As Int32, ByVal mouseY As Int32, _
                                                   ByVal buttons As Byte, _
                                                   ByVal screenW As Int32, ByVal screenH As Int32) As Boolean
        Dim stateChanged As Boolean = False
        Dim leftClicked As Boolean = ((buttons And 1) <> 0) And ((lastButtons And 1) = 0)
        Dim leftReleased As Boolean = ((buttons And 1) = 0) And ((lastButtons And 1) <> 0)

        ' 1. On left button press: perform hit-testing in top-down Z-order
        If leftClicked Then
            Dim hitTarget As Pointer To WindowItem = 0
            Dim hitCode As UInt32 = HIT_NONE

            Dim i As Int32 = CType(Int32, windowCount) - 1
            While i >= 0
                Dim pWin As Pointer To WindowItem = CPtr(Pointer To WindowItem, AddressOf windows(i))
                If pWin.State <> WIN_STATE_MINIMIZED Then
                    Dim code As UInt32 = HitTestWindow(mouseX, mouseY, pWin.X, pWin.Y, pWin.Width, pWin.Height)
                    If code <> HIT_NONE Then
                        hitTarget = pWin
                        hitCode = code
                        Exit While
                    End If
                End If
                i = i - 1
            Wend

            If hitTarget <> 0 Then
                Dim targetId As UInt32 = hitTarget.Id
                SetFocus targetId
                hitTarget = FindWindow(targetId)
                stateChanged = True

                If hitCode = HIT_BTN_CLOSE Then
                    DestroyWindow targetId
                ElseIf hitCode = HIT_BTN_MAX Then
                    If hitTarget.State = WIN_STATE_MAXIMIZED Then
                        RestoreWindow targetId
                    Else
                        MaximizeWindow targetId, screenW, screenH
                    End If
                ElseIf hitCode = HIT_BTN_MIN Then
                    MinimizeWindow targetId
                ElseIf hitCode = HIT_TITLEBAR Then
                    If hitTarget.State = WIN_STATE_NORMAL Then
                        hitTarget.Dragging = True
                        hitTarget.DragOffsetX = mouseX - hitTarget.X
                        hitTarget.DragOffsetY = mouseY - hitTarget.Y
                    End If
                ElseIf hitCode = HIT_RESIZE_BR Then
                    If hitTarget.State = WIN_STATE_NORMAL Then
                        hitTarget.Resizing = True
                        hitTarget.DragOffsetX = (hitTarget.X + hitTarget.Width) - mouseX
                        hitTarget.DragOffsetY = (hitTarget.Y + hitTarget.Height) - mouseY
                    End If
                End If
            End If
        End If

        ' 2. On left button release: end all dragging and resizing operations
        If leftReleased Then
            Dim j As UInt32 = 0
            While j < windowCount
                If windows(j).Dragging Or windows(j).Resizing Then
                    stateChanged = True
                End If
                windows(j).Dragging = False
                windows(j).Resizing = False
                j = j + 1
            Wend
        End If

        ' 3. While mouse moves with left button held: update dragging or resizing geometry
        If (buttons And 1) <> 0 Then
            Dim k As UInt32 = 0
            While k < windowCount
                Dim win As Pointer To WindowItem = CPtr(Pointer To WindowItem, AddressOf windows(k))
                If win.Dragging And win.State = WIN_STATE_NORMAL Then
                    Dim newX As Int32 = mouseX - win.DragOffsetX
                    Dim newY As Int32 = mouseY - win.DragOffsetY

                    ' Magnetic edge snapping within 16px of screen boundaries
                    Dim snapDist As Int32 = 16
                    If newX >= -snapDist And newX <= snapDist Then
                        newX = 0
                    ElseIf (newX + win.Width) >= (screenW - snapDist) And (newX + win.Width) <= (screenW + snapDist) Then
                        newX = screenW - win.Width
                    End If

                    If (newY - 26) >= -snapDist And (newY - 26) <= snapDist Then
                        newY = 26
                    ElseIf (newY + win.Height) >= (screenH - snapDist) And (newY + win.Height) <= (screenH + snapDist) Then
                        newY = screenH - win.Height
                    End If

                    ' Screen overflow limits (keep titlebar accessible below top bar, at least 48px visible)
                    If newY < 26 Then newY = 26
                    If newY > (screenH - 26) Then newY = screenH - 26
                    If newX < -(win.Width - 48) Then newX = -(win.Width - 48)
                    If newX > (screenW - 48) Then newX = screenW - 48

                    If win.X <> newX Or win.Y <> newY Then
                        win.X = newX
                        win.Y = newY
                        stateChanged = True
                    End If
                ElseIf win.Resizing And win.State = WIN_STATE_NORMAL Then
                    Dim targetW As Int32 = (mouseX + win.DragOffsetX) - win.X
                    Dim targetH As Int32 = (mouseY + win.DragOffsetY) - win.Y

                    If targetW < 160 Then targetW = 160
                    If targetH < 100 Then targetH = 100
                    If (win.X + targetW) > screenW Then targetW = screenW - win.X
                    If (win.Y + targetH) > screenH Then targetH = screenH - win.Y

                    If win.Width <> targetW Or win.Height <> targetH Then
                        win.Width = targetW
                        win.Height = targetH
                        stateChanged = True
                    End If
                End If
                k = k + 1
            Wend
        End If

        lastMouseX = mouseX
        lastMouseY = mouseY
        lastButtons = buttons
        ProcessMouseInteraction = stateChanged
    End Function

    ''
    ' @brief Application entry point for wm daemon (Ring 3 CPL=3).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[WM] ======================================================="
        ConsoleWriteLine "[WM] PROS Window Manager Service Daemon Online (CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[WM] Active Service PID = ", myPid, "\r\n"

        ' 2. Register Window Manager Node
        Dim wmNodeId As UInt64 = NodeRegister(2, CPtr(Pointer To Byte, "srv.wm"), 7)
        If wmNodeId <> 0 Then
            ConsolePrintWithUInt "[WM] Registered Node 'srv.wm' -> Node #", wmNodeId, "\r\n"
        Else
            ConsoleWriteLine "[WM] WARN: Failed to register 'srv.wm' node!"
        End If

        ' 4. Allocate Shared Memory WindowTable at 0x62000000
        shmTableId = ShmemCreate(SizeOf(WindowTable), &H62000000)
        pWindowTable = CPtr(Pointer To WindowTable, &H62000000)
        If pWindowTable <> 0 Then
            pWindowTable.Revision = 1
            pWindowTable.Count = 0
            ConsolePrintWithUInt "[WM] Shared WindowTable allocated (SHMID: ", shmTableId, " @ 0x62000000)\r\n"
        End If

        ' 5. Connect to Compositor and Input Services
        Dim compNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.compositor"))
        Dim synComp As UInt64 = 0
        If compNodeId <> 0 Then
            ConsolePrintWithUInt "[WM] Attached to Display Compositor -> Node #", compNodeId, "\r\n"
            synComp = SynapseConnect(wmNodeId, compNodeId, 7)
            If synComp <> 0 Then
                ConsolePrintWithUInt "[WM] Established Compositor Control Synapse -> Channel #", synComp, "\r\n"
                ' Register WindowTable with Compositor
                Dim regPkt As AxonPacket
                regPkt.Sequence = 1
                regPkt.PacketType = WM_CMD_REGISTER_TABLE
                regPkt.SourceNode = wmNodeId
                regPkt.TargetNode = compNodeId
                Dim pShmPayload As Pointer To UInt64 = CPtr(Pointer To UInt64, @regPkt.Payload(0))
                pShmPayload(0) = shmTableId
                regPkt.PayloadLength = 8
                SynapsePush synComp, regPkt
            End If
        End If

        Dim inputNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.input"))
        Dim synInput As UInt64 = 0
        If inputNodeId <> 0 Then
            ConsolePrintWithUInt "[WM] Attached to Input Subsystem -> Node #", inputNodeId, "\r\n"
            synInput = SynapseConnect(wmNodeId, inputNodeId, 7)
            If synInput <> 0 Then
                ConsolePrintWithUInt "[WM] Established Input Event Synapse -> Channel #", synInput, "\r\n"
            End If
        End If

        ' 6. Initialize Desktop Window Tree
        InitWindows
        ConsolePrintWithUInt "[WM] Initialized Window Tree: ", CType(UInt64, windowCount), " Managed Windows\r\n"
        ConsoleWriteLine "[WM] Decoupled WindowTheme Engine loaded (Nord Palette & 10x10 Glyphs)"
        ConsoleWriteLine "[WM] Window arbitration active. Entering event loop..."
        ConsoleWriteLine "[WM] ======================================================="

        ' 7. Active event loop (Zero idle CPU via SynapsePopWait)
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim wmReqCount As UInt64 = 0

        Do
            ' Service incoming window manager requests from compositor / client applications
            If SynapsePopWait(wmNodeId, reqPkt) Then
                If reqPkt.PacketType = WM_CMD_CREATE_WINDOW Then
                    Dim pW As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(0))
                    Dim pH As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(4))
                    Dim pShm As Pointer To UInt64 = CPtr(Pointer To UInt64, @reqPkt.Payload(8))
                    Dim w As Int32 = pW(0)
                    Dim h As Int32 = pH(0)
                    Dim shmId As UInt64 = pShm(0)

                    Dim newId As UInt32 = windowCount + 1
                    Dim newX As Int32 = 60 + CType(Int32, windowCount * 50)
                    Dim newY As Int32 = 60 + CType(Int32, windowCount * 40)
                    If (newX + w) > 1024 Then newX = 40
                    If (newY + h) > 768 Then newY = 40

                    Dim titleBuf(32) As Byte
                    Dim t As UInt32 = 0
                    While t < 31
                        titleBuf(t) = reqPkt.Payload(16 + t)
                        t = t + 1
                    Wend
                    titleBuf(31) = 0

                    AddWindow newId, reqPkt.SourceNode, newX, newY, w, h, 0, shmId, @titleBuf(0)
                    SetFocus newId
                    SyncWindowTable

                    respPkt.Sequence = wmReqCount
                    respPkt.SourceNode = wmNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    respPkt.PacketType = WM_RESP_OK
                    Dim pResId As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(0))
                    pResId(0) = newId
                    respPkt.PayloadLength = 4

                    Dim replyChan As UInt64 = SynapseConnect(wmNodeId, reqPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If
                    wmReqCount = wmReqCount + 1

                    ' Notify compositor to refresh desktop scene
                    If synComp = 0 Then
                        compNodeId = NodeLookup(CPtr(Pointer To Byte, "srv.compositor"))
                        If compNodeId <> 0 Then
                            synComp = SynapseConnect(wmNodeId, compNodeId, 7)
                        End If
                    End If
                    If synComp <> 0 Then
                        Dim notifyDirtyPkt As AxonPacket
                        notifyDirtyPkt.Sequence = wmReqCount
                        notifyDirtyPkt.SourceNode = wmNodeId
                        notifyDirtyPkt.TargetNode = compNodeId
                        notifyDirtyPkt.PacketType = WM_CMD_WINDOW_DIRTY
                        notifyDirtyPkt.PayloadLength = 0
                        SynapsePush synComp, notifyDirtyPkt
                    End If
                ElseIf reqPkt.PacketType = WM_CMD_REGISTER_TABLE Then
                    compNodeId = reqPkt.SourceNode
                    If synComp = 0 Then
                        synComp = SynapseConnect(wmNodeId, compNodeId, 7)
                    End If
                    respPkt.Sequence = wmReqCount
                    respPkt.SourceNode = wmNodeId
                    respPkt.TargetNode = compNodeId
                    respPkt.PacketType = WM_CMD_REGISTER_TABLE
                    Dim pShmResp As Pointer To UInt64 = CPtr(Pointer To UInt64, @respPkt.Payload(0))
                    pShmResp(0) = shmTableId
                    respPkt.PayloadLength = 8
                    If synComp <> 0 Then
                        SynapsePush synComp, respPkt
                    End If
                    wmReqCount = wmReqCount + 1
                ElseIf reqPkt.PacketType = WM_CMD_MOUSE_EVENT Then
                    Dim pMx As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(0))
                    Dim pMy As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(4))
                    Dim pBtn As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(8))
                    Dim changed As Boolean = ProcessMouseInteraction(pMx(0), pMy(0), CType(Byte, pBtn(0)), 1024, 768)
                    If changed Then
                        SyncWindowTable
                        If synComp <> 0 Then
                            Dim mDirtyPkt As AxonPacket
                            mDirtyPkt.Sequence = wmReqCount
                            mDirtyPkt.SourceNode = wmNodeId
                            mDirtyPkt.TargetNode = compNodeId
                            mDirtyPkt.PacketType = WM_CMD_WINDOW_DIRTY
                            mDirtyPkt.PayloadLength = 0
                            SynapsePush synComp, mDirtyPkt
                        End If
                    End If
                ElseIf reqPkt.PacketType = WM_CMD_SET_FOCUS Then
                    Dim pWinId As Pointer To UInt32 = CPtr(Pointer To UInt32, @reqPkt.Payload(0))
                    Dim ok As Boolean = SetFocus(pWinId(0))
                    SyncWindowTable
                    respPkt.Sequence = wmReqCount
                    respPkt.SourceNode = wmNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    If ok Then
                        respPkt.PacketType = WM_RESP_OK
                    Else
                        respPkt.PacketType = WM_RESP_ERROR
                    End If
                    respPkt.PayloadLength = 0

                    Dim replyChan2 As UInt64 = SynapseConnect(wmNodeId, reqPkt.SourceNode, 7)
                    If replyChan2 <> 0 Then
                        SynapsePush replyChan2, respPkt
                    End If
                    wmReqCount = wmReqCount + 1
                ElseIf reqPkt.PacketType = WM_CMD_DESTROY_WINDOW Then
                    Dim pWinId2 As Pointer To UInt32 = CPtr(Pointer To UInt32, @reqPkt.Payload(0))
                    Dim ok2 As Boolean = DestroyWindow(pWinId2(0))
                    SyncWindowTable
                    respPkt.Sequence = wmReqCount
                    respPkt.SourceNode = wmNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    If ok2 Then
                        respPkt.PacketType = WM_RESP_OK
                    Else
                        respPkt.PacketType = WM_RESP_ERROR
                    End If
                    respPkt.PayloadLength = 0

                    Dim replyChan3 As UInt64 = SynapseConnect(wmNodeId, reqPkt.SourceNode, 7)
                    If replyChan3 <> 0 Then
                        SynapsePush replyChan3, respPkt
                    End If
                    wmReqCount = wmReqCount + 1

                    If synComp <> 0 Then
                        Dim dDirtyPkt As AxonPacket
                        dDirtyPkt.Sequence = wmReqCount
                        dDirtyPkt.SourceNode = wmNodeId
                        dDirtyPkt.TargetNode = compNodeId
                        dDirtyPkt.PacketType = WM_CMD_WINDOW_DIRTY
                        dDirtyPkt.PayloadLength = 0
                        SynapsePush synComp, dDirtyPkt
                    End If
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
