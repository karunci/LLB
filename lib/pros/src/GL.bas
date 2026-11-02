' Project Name: LibPROS / Low-Level Basic
' Filename: lib/pros/src/GL.bas
' Summary: Standalone Ring 3 Software 3D OpenGL Rasterizer engine and matrix pipeline.

Module GL

    ' -------------------------------------------------------------------------
    ' OpenGL Core Constants
    ' -------------------------------------------------------------------------
    Public Const GL_COLOR_BUFFER_BIT As UInt32 = 1
    Public Const GL_DEPTH_BUFFER_BIT As UInt32 = 2

    Public Const GL_MODELVIEW        As Int32 = 0
    Public Const GL_PROJECTION       As Int32 = 1

    Public Const GL_TRIANGLES        As Int32 = 0
    Public Const GL_QUADS            As Int32 = 1
    Public Const GL_LINES            As Int32 = 2

    Public Const GL_DEPTH_TEST       As UInt32 = 1
    Public Const GL_CULL_FACE        As UInt32 = 2

    Private Const PI                 As Single = 3.14159265
    Private Const TWO_PI             As Single = 6.2831853
    Private Const DEG2RAD            As Single = 0.0174532925

    ' -------------------------------------------------------------------------
    ' Mathematical Structures
    ' -------------------------------------------------------------------------
    <Packed>
    Public Structure GlVec3
        Public X As Single
        Public Y As Single
        Public Z As Single
    End Structure

    <Packed>
    Public Structure GlVec4
        Public X As Single
        Public Y As Single
        Public Z As Single
        Public W As Single
    End Structure

    <Packed>
    Public Structure GlMat4
        Public M(16) As Single
    End Structure

    <Packed>
    Public Structure GlVertex
        Public X As Single
        Public Y As Single
        Public Z As Single
        Public Color As UInt32
        Public U As Single
        Public V As Single
    End Structure

    ' -------------------------------------------------------------------------
    ' Global Rasterizer State
    ' -------------------------------------------------------------------------
    Private pColorBuf As Pointer To UInt32 = 0
    Private pDepthBuf As Pointer To Single = 0
    Private bufW As Int32 = 0
    Private bufH As Int32 = 0

    Private vpX As Int32 = 0
    Private vpY As Int32 = 0
    Private vpW As Int32 = 0
    Private vpH As Int32 = 0

    Private clearCol As UInt32 = &HFF000000
    Private clearD As Single = 1.0
    Private depthTestActive As Boolean = True
    Private cullFaceActive As Boolean = False

    Private matMode As Int32 = GL_MODELVIEW
    Private modelviewStack(16) As GlMat4
    Private modelviewDepth As Int32 = 0
    Private projectionStack(4) As GlMat4
    Private projectionDepth As Int32 = 0

    Private curColor As UInt32 = &HFFFFFFFF
    Private curU As Single = 0.0
    Private curV As Single = 0.0

    Private beginMode As Int32 = -1
    Private batch(64) As GlVertex
    Private batchCount As Int32 = 0

    ' -------------------------------------------------------------------------
    ' Fast Trigonometric Functions
    ' -------------------------------------------------------------------------
    ''
    ' @brief High-precision polynomial sine approximation.
    ' @param rad Angle in radians.
    ' @return Sine value in [-1.0, 1.0].
    ''
    Public Function FastSin(ByVal rad As Single) As Single
        While rad > PI
            rad = rad - TWO_PI
        Wend
        While rad < -PI
            rad = rad + TWO_PI
        Wend
        Dim x2 As Single = rad * rad
        Dim x3 As Single = rad * x2
        Dim x5 As Single = x3 * x2
        Dim x7 As Single = x5 * x2
        FastSin = rad - (x3 * 0.16666667) + (x5 * 0.00833333) - (x7 * 0.00019841)
    End Function

    ''
    ' @brief High-precision polynomial cosine approximation.
    ' @param rad Angle in radians.
    ' @return Cosine value in [-1.0, 1.0].
    ''
    Public Function FastCos(ByVal rad As Single) As Single
        FastCos = FastSin(rad + (PI * 0.5))
    End Function

    ' -------------------------------------------------------------------------
    ' 4x4 Matrix Mathematics
    ' -------------------------------------------------------------------------
    ''
    ' @brief Initialize matrix to 4x4 identity.
    ' @param m Matrix to initialize.
    ''
    Public Sub Mat4Identity(ByRef m As GlMat4)
        Dim i As Int32 = 0
        While i < 16
            m.M(i) = 0.0
            i = i + 1
        Wend
        m.M(0) = 1.0
        m.M(5) = 1.0
        m.M(10) = 1.0
        m.M(15) = 1.0
    End Sub

    ''
    ' @brief Multiply two 4x4 matrices (out = a * b).
    ''
    Public Sub Mat4Multiply(ByRef out As GlMat4, ByRef a As GlMat4, ByRef b As GlMat4)
        Dim res As GlMat4
        Dim r As Int32 = 0
        While r < 4
            Dim c As Int32 = 0
            While c < 4
                Dim sum As Single = 0.0
                Dim k As Int32 = 0
                While k < 4
                    sum = sum + (a.M((r * 4) + k) * b.M((k * 4) + c))
                    k = k + 1
                Wend
                res.M((r * 4) + c) = sum
                c = c + 1
            Wend
            r = r + 1
        Wend
        out = res
    End Sub

    ' -------------------------------------------------------------------------
    ' OpenGL Initialization & Configuration
    ' -------------------------------------------------------------------------
    ''
    ' @brief Initialize OpenGL software rendering context with color & depth buffers.
    ' @param width Framebuffer width in pixels.
    ' @param height Framebuffer height in pixels.
    ' @param pColor Pointer to 32-bit ARGB color buffer in memory.
    ' @param pDepth Pointer to 32-bit float depth buffer in memory.
    ''
    Public Sub GlInit(ByVal width As Int32, ByVal height As Int32, ByVal pColor As Pointer To UInt32, ByVal pDepth As Pointer To Single)
        bufW = width
        bufH = height
        pColorBuf = pColor
        pDepthBuf = pDepth

        vpX = 0
        vpY = 0
        vpW = width
        vpH = height

        Mat4Identity modelviewStack(0)
        modelviewDepth = 0

        Mat4Identity projectionStack(0)
        projectionDepth = 0

        depthTestActive = True
        cullFaceActive = False
    End Sub

    ''
    ' @brief Set viewport rectangle for normalized device coordinate mapping.
    ''
    Public Sub GlViewport(ByVal x As Int32, ByVal y As Int32, ByVal width As Int32, ByVal height As Int32)
        vpX = x
        vpY = y
        vpW = width
        vpH = height
    End Sub

    ''
    ' @brief Set RGBA clear color.
    ''
    Public Sub GlClearColor(ByVal r As Single, ByVal g As Single, ByVal b As Single, ByVal a As Single)
        Dim ir As UInt32 = UInt32(r * 255.0)
        Dim ig As UInt32 = UInt32(g * 255.0)
        Dim ib As UInt32 = UInt32(b * 255.0)
        Dim ia As UInt32 = UInt32(a * 255.0)
        If ir > 255 Then ir = 255
        If ig > 255 Then ig = 255
        If ib > 255 Then ib = 255
        If ia > 255 Then ia = 255
        clearCol = (ia LShift 24) Or (ir LShift 16) Or (ig LShift 8) Or ib
    End Sub

    ''
    ' @brief Set depth clear value.
    ''
    Public Sub GlClearDepth(ByVal depth As Single)
        clearD = depth
    End Sub

    ''
    ' @brief Clear color and/or depth buffers.
    ''
    Public Sub GlClear(ByVal mask As UInt32)
        If pColorBuf = 0 Or bufW <= 0 Or bufH <= 0 Then Exit Sub
        Dim totalPixels As Int32 = bufW * bufH
        Dim localColorBuf As Pointer To UInt32 = pColorBuf
        Dim localDepthBuf As Pointer To Single = pDepthBuf

        If (mask And GL_COLOR_BUFFER_BIT) <> 0 Then
            Dim i As Int32 = 0
            While i < totalPixels
                localColorBuf(i) = clearCol
                i = i + 1
            Wend
        End If

        If (mask And GL_DEPTH_BUFFER_BIT) <> 0 And localDepthBuf <> 0 Then
            Dim j As Int32 = 0
            While j < totalPixels
                localDepthBuf(j) = clearD
                j = j + 1
            Wend
        End If
    End Sub

    ''
    ' @brief Enable OpenGL rendering capability.
    ''
    Public Sub GlEnable(ByVal cap As UInt32)
        If cap = GL_DEPTH_TEST Then depthTestActive = True
        If cap = GL_CULL_FACE Then cullFaceActive = True
    End Sub

    ''
    ' @brief Disable OpenGL rendering capability.
    ''
    Public Sub GlDisable(ByVal cap As UInt32)
        If cap = GL_DEPTH_TEST Then depthTestActive = False
        If cap = GL_CULL_FACE Then cullFaceActive = False
    End Sub

    ' -------------------------------------------------------------------------
    ' Matrix Operations & Stack Management
    ' -------------------------------------------------------------------------
    ''
    ' @brief Select active matrix stack (GL_MODELVIEW or GL_PROJECTION).
    ''
    Public Sub GlMatrixMode(ByVal mode As Int32)
        matMode = mode
    End Sub

    ''
    ' @brief Reset current matrix to identity.
    ''
    Public Sub GlLoadIdentity()
        If matMode = GL_MODELVIEW Then
            Mat4Identity modelviewStack(modelviewDepth)
        Else
            Mat4Identity projectionStack(projectionDepth)
        End If
    End Sub

    ''
    ' @brief Push current matrix onto the active stack.
    ''
    Public Sub GlPushMatrix()
        If matMode = GL_MODELVIEW Then
            If modelviewDepth < 15 Then
                modelviewStack(modelviewDepth + 1) = modelviewStack(modelviewDepth)
                modelviewDepth = modelviewDepth + 1
            End If
        Else
            If projectionDepth < 3 Then
                projectionStack(projectionDepth + 1) = projectionStack(projectionDepth)
                projectionDepth = projectionDepth + 1
            End If
        End If
    End Sub

    ''
    ' @brief Pop top matrix from the active stack.
    ''
    Public Sub GlPopMatrix()
        If matMode = GL_MODELVIEW Then
            If modelviewDepth > 0 Then
                modelviewDepth = modelviewDepth - 1
            End If
        Else
            If projectionDepth > 0 Then
                projectionDepth = projectionDepth - 1
            End If
        End If
    End Sub

    ''
    ' @brief Multiply current matrix by a translation matrix.
    ''
    Public Sub GlTranslatef(ByVal tx As Single, ByVal ty As Single, ByVal tz As Single)
        Dim t As GlMat4
        Mat4Identity t
        t.M(3) = tx
        t.M(7) = ty
        t.M(11) = tz

        If matMode = GL_MODELVIEW Then
            Mat4Multiply modelviewStack(modelviewDepth), modelviewStack(modelviewDepth), t
        Else
            Mat4Multiply projectionStack(projectionDepth), projectionStack(projectionDepth), t
        End If
    End Sub

    ''
    ' @brief Multiply current matrix by a scaling matrix.
    ''
    Public Sub GlScalef(ByVal sx As Single, ByVal sy As Single, ByVal sz As Single)
        Dim s As GlMat4
        Mat4Identity s
        s.M(0) = sx
        s.M(5) = sy
        s.M(10) = sz

        If matMode = GL_MODELVIEW Then
            Mat4Multiply modelviewStack(modelviewDepth), modelviewStack(modelviewDepth), s
        Else
            Mat4Multiply projectionStack(projectionDepth), projectionStack(projectionDepth), s
        End If
    End Sub

    ''
    ' @brief Multiply current matrix by a rotation matrix around arbitrary axis (x, y, z).
    ''
    Public Sub GlRotatef(ByVal angleDeg As Single, ByVal x As Single, ByVal y As Single, ByVal z As Single)
        Dim rad As Single = angleDeg * DEG2RAD
        Dim c As Single = FastCos(rad)
        Dim s As Single = FastSin(rad)
        Dim t As Single = 1.0 - c

        Dim rot As GlMat4
        Mat4Identity rot

        If x > 0.9 And y < 0.1 And z < 0.1 Then
            ' Pure X rotation
            rot.M(5) = c
            rot.M(6) = -s
            rot.M(9) = s
            rot.M(10) = c
        ElseIf y > 0.9 And x < 0.1 And z < 0.1 Then
            ' Pure Y rotation
            rot.M(0) = c
            rot.M(2) = s
            rot.M(8) = -s
            rot.M(10) = c
        ElseIf z > 0.9 And x < 0.1 And y < 0.1 Then
            ' Pure Z rotation
            rot.M(0) = c
            rot.M(1) = -s
            rot.M(4) = s
            rot.M(5) = c
        Else
            ' General axis rotation
            rot.M(0) = (t * x * x) + c
            rot.M(1) = (t * x * y) - (s * z)
            rot.M(2) = (t * x * z) + (s * y)

            rot.M(4) = (t * x * y) + (s * z)
            rot.M(5) = (t * y * y) + c
            rot.M(6) = (t * y * z) - (s * x)

            rot.M(8) = (t * x * z) - (s * y)
            rot.M(9) = (t * y * z) + (s * x)
            rot.M(10) = (t * z * z) + c
        End If

        If matMode = GL_MODELVIEW Then
            Mat4Multiply modelviewStack(modelviewDepth), modelviewStack(modelviewDepth), rot
        Else
            Mat4Multiply projectionStack(projectionDepth), projectionStack(projectionDepth), rot
        End If
    End Sub

    ''
    ' @brief Set perspective projection matrix matching gluPerspective.
    ''
    Public Sub GluPerspective(ByVal fovYDeg As Single, ByVal aspect As Single, ByVal zNear As Single, ByVal zFar As Single)
        Dim fovRad As Single = fovYDeg * DEG2RAD
        Dim tanHalf As Single = FastSin(fovRad * 0.5) / FastCos(fovRad * 0.5)
        If tanHalf < 0.0001 Then tanHalf = 0.0001
        Dim f As Single = 1.0 / tanHalf

        Dim p As GlMat4
        Dim i As Int32 = 0
        While i < 16
            p.M(i) = 0.0
            i = i + 1
        Wend

        p.M(0) = f / aspect
        p.M(5) = f
        p.M(10) = (zFar + zNear) / (zNear - zFar)
        p.M(11) = (2.0 * zFar * zNear) / (zNear - zFar)
        p.M(14) = -1.0
        p.M(15) = 0.0

        If matMode = GL_PROJECTION Then
            Mat4Multiply projectionStack(projectionDepth), projectionStack(projectionDepth), p
        Else
            Mat4Multiply modelviewStack(modelviewDepth), modelviewStack(modelviewDepth), p
        End If
    End Sub

    ' -------------------------------------------------------------------------
    ' Geometry Submission (Immediate Mode)
    ' -------------------------------------------------------------------------
    ''
    ' @brief Begin primitive assembly (GL_TRIANGLES, GL_QUADS).
    ''
    Public Sub GlBegin(ByVal mode As Int32)
        beginMode = mode
        batchCount = 0
    End Sub

    ''
    ' @brief Set current RGB/RGBA vertex color.
    ''
    Public Sub GlColor4f(ByVal r As Single, ByVal g As Single, ByVal b As Single, ByVal a As Single)
        Dim ir As UInt32 = UInt32(r * 255.0)
        Dim ig As UInt32 = UInt32(g * 255.0)
        Dim ib As UInt32 = UInt32(b * 255.0)
        Dim ia As UInt32 = UInt32(a * 255.0)
        If ir > 255 Then ir = 255
        If ig > 255 Then ig = 255
        If ib > 255 Then ib = 255
        If ia > 255 Then ia = 255
        curColor = (ia LShift 24) Or (ir LShift 16) Or (ig LShift 8) Or ib
    End Sub

    ''
    ' @brief Set current vertex texture coordinates.
    ''
    Public Sub GlTexCoord2f(ByVal u As Single, ByVal v As Single)
        curU = u
        curV = v
    End Sub

    ''
    ' @brief Submit 3D vertex position.
    ''
    Public Sub GlVertex3f(ByVal x As Single, ByVal y As Single, ByVal z As Single)
        If batchCount < 64 Then
            batch(batchCount).X = x
            batch(batchCount).Y = y
            batch(batchCount).Z = z
            batch(batchCount).Color = curColor
            batch(batchCount).U = curU
            batch(batchCount).V = curV
            batchCount = batchCount + 1
        End If
    End Sub

    ' -------------------------------------------------------------------------
    ' Scanline Triangle Rasterizer with Z-Buffering & Gouraud Shading
    ' -------------------------------------------------------------------------
    Private Sub RasterizeTriangle(ByRef mvp As GlMat4, ByRef v0 As GlVertex, ByRef v1 As GlVertex, ByRef v2 As GlVertex)
        ' 1. Transform vertices to clip space: (cx, cy, cz, cw) = MVP * (x, y, z, 1.0)
        Dim c0X As Single = (mvp.M(0)*v0.X) + (mvp.M(1)*v0.Y) + (mvp.M(2)*v0.Z) + mvp.M(3)
        Dim c0Y As Single = (mvp.M(4)*v0.X) + (mvp.M(5)*v0.Y) + (mvp.M(6)*v0.Z) + mvp.M(7)
        Dim c0Z As Single = (mvp.M(8)*v0.X) + (mvp.M(9)*v0.Y) + (mvp.M(10)*v0.Z) + mvp.M(11)
        Dim c0W As Single = (mvp.M(12)*v0.X) + (mvp.M(13)*v0.Y) + (mvp.M(14)*v0.Z) + mvp.M(15)

        Dim c1X As Single = (mvp.M(0)*v1.X) + (mvp.M(1)*v1.Y) + (mvp.M(2)*v1.Z) + mvp.M(3)
        Dim c1Y As Single = (mvp.M(4)*v1.X) + (mvp.M(5)*v1.Y) + (mvp.M(6)*v1.Z) + mvp.M(7)
        Dim c1Z As Single = (mvp.M(8)*v1.X) + (mvp.M(9)*v1.Y) + (mvp.M(10)*v1.Z) + mvp.M(11)
        Dim c1W As Single = (mvp.M(12)*v1.X) + (mvp.M(13)*v1.Y) + (mvp.M(14)*v1.Z) + mvp.M(15)

        Dim c2X As Single = (mvp.M(0)*v2.X) + (mvp.M(1)*v2.Y) + (mvp.M(2)*v2.Z) + mvp.M(3)
        Dim c2Y As Single = (mvp.M(4)*v2.X) + (mvp.M(5)*v2.Y) + (mvp.M(6)*v2.Z) + mvp.M(7)
        Dim c2Z As Single = (mvp.M(8)*v2.X) + (mvp.M(9)*v2.Y) + (mvp.M(10)*v2.Z) + mvp.M(11)
        Dim c2W As Single = (mvp.M(12)*v2.X) + (mvp.M(13)*v2.Y) + (mvp.M(14)*v2.Z) + mvp.M(15)

        ' Near plane culling
        If c0W < 0.05 Or c1W < 0.05 Or c2W < 0.05 Then Exit Sub

        ' 2. Perspective division -> NDC [-1.0, 1.0]
        Dim invW0 As Single = 1.0 / c0W
        Dim invW1 As Single = 1.0 / c1W
        Dim invW2 As Single = 1.0 / c2W

        Dim ndc0X As Single = c0X * invW0
        Dim ndc0Y As Single = c0Y * invW0
        Dim ndc0Z As Single = c0Z * invW0

        Dim ndc1X As Single = c1X * invW1
        Dim ndc1Y As Single = c1Y * invW1
        Dim ndc1Z As Single = c1Z * invW1

        Dim ndc2X As Single = c2X * invW2
        Dim ndc2Y As Single = c2Y * invW2
        Dim ndc2Z As Single = c2Z * invW2

        ' 3. Viewport mapping to screen coordinates
        Dim halfW As Single = Single(vpW) * 0.5
        Dim halfH As Single = Single(vpH) * 0.5

        Dim sx0 As Int32 = vpX + Int32((ndc0X + 1.0) * halfW)
        Dim sy0 As Int32 = vpY + Int32((1.0 - ndc0Y) * halfH)
        Dim sz0 As Single = (ndc0Z + 1.0) * 0.5

        Dim sx1 As Int32 = vpX + Int32((ndc1X + 1.0) * halfW)
        Dim sy1 As Int32 = vpY + Int32((1.0 - ndc1Y) * halfH)
        Dim sz1 As Single = (ndc1Z + 1.0) * 0.5

        Dim sx2 As Int32 = vpX + Int32((ndc2X + 1.0) * halfW)
        Dim sy2 As Int32 = vpY + Int32((1.0 - ndc2Y) * halfH)
        Dim sz2 As Single = (ndc2Z + 1.0) * 0.5

        ' 4. Backface culling
        Dim area As Int32 = ((sx1 - sx0) * (sy2 - sy0)) - ((sy1 - sy0) * (sx2 - sx0))
        If cullFaceActive And area <= 0 Then Exit Sub
        If area = 0 Then Exit Sub

        ' 5. Bounding box computation & viewport clipping
        Dim minX As Int32 = sx0
        If sx1 < minX Then minX = sx1
        If sx2 < minX Then minX = sx2

        Dim maxX As Int32 = sx0
        If sx1 > maxX Then maxX = sx1
        If sx2 > maxX Then maxX = sx2

        Dim minY As Int32 = sy0
        If sy1 < minY Then minY = sy1
        If sy2 < minY Then minY = sy2

        Dim maxY As Int32 = sy0
        If sy1 > maxY Then maxY = sy1
        If sy2 > maxY Then maxY = sy2

        If minX < vpX Then minX = vpX
        If maxX >= (vpX + vpW) Then maxX = (vpX + vpW) - 1
        If minY < vpY Then minY = vpY
        If maxY >= (vpY + vpH) Then maxY = (vpY + vpH) - 1
        If minX > maxX Or minY > maxY Then Exit Sub

        ' 6. Vertex colors (R, G, B)
        Dim r0 As Single = Single((v0.Color RShift 16) And &HFF)
        Dim g0 As Single = Single((v0.Color RShift 8) And &HFF)
        Dim b0 As Single = Single(v0.Color And &HFF)

        Dim r1 As Single = Single((v1.Color RShift 16) And &HFF)
        Dim g1 As Single = Single((v1.Color RShift 8) And &HFF)
        Dim b1 As Single = Single(v1.Color And &HFF)

        Dim r2 As Single = Single((v2.Color RShift 16) And &HFF)
        Dim g2 As Single = Single((v2.Color RShift 8) And &HFF)
        Dim b2 As Single = Single(v2.Color And &HFF)

        Dim invArea As Single = 1.0 / Single(area)
        Dim localColorBuf As Pointer To UInt32 = pColorBuf
        Dim localDepthBuf As Pointer To Single = pDepthBuf
        If localColorBuf = 0 Then Exit Sub

        ' 7. Barycentric scanline rasterization loop
        Dim py As Int32 = minY
        While py <= maxY
            Dim px As Int32 = minX
            While px <= maxX
                Dim w0 As Int32 = ((sx2 - sx1) * (py - sy1)) - ((sy2 - sy1) * (px - sx1))
                Dim w1 As Int32 = ((sx0 - sx2) * (py - sy2)) - ((sy0 - sy2) * (px - sx2))
                Dim w2 As Int32 = ((sx1 - sx0) * (py - sy0)) - ((sy1 - sy0) * (px - sx0))

                Dim inside As Boolean = False
                If area > 0 Then
                    If w0 >= 0 And w1 >= 0 And w2 >= 0 Then inside = True
                Else
                    If w0 <= 0 And w1 <= 0 And w2 <= 0 Then inside = True
                End If

                If inside Then
                    Dim f0 As Single = Single(w0) * invArea
                    Dim f1 As Single = Single(w1) * invArea
                    Dim f2 As Single = Single(w2) * invArea

                    Dim pixZ As Single = (f0 * sz0) + (f1 * sz1) + (f2 * sz2)
                    Dim idx As Int32 = (py * bufW) + px

                    Dim passDepth As Boolean = True
                    If depthTestActive And localDepthBuf <> 0 Then
                        If pixZ >= localDepthBuf(idx) Then passDepth = False
                    End If

                    If passDepth Then
                        If depthTestActive And localDepthBuf <> 0 Then
                            localDepthBuf(idx) = pixZ
                        End If

                        Dim pr As UInt32 = UInt32((f0 * r0) + (f1 * r1) + (f2 * r2))
                        Dim pg As UInt32 = UInt32((f0 * g0) + (f1 * g1) + (f2 * g2))
                        Dim pb As UInt32 = UInt32((f0 * b0) + (f1 * b1) + (f2 * b2))
                        If pr > 255 Then pr = 255
                        If pg > 255 Then pg = 255
                        If pb > 255 Then pb = 255

                        localColorBuf(idx) = &HFF000000 Or (pr LShift 16) Or (pg LShift 8) Or pb
                    End If
                End If
                px = px + 1
            Wend
            py = py + 1
        Wend
    End Sub

    ''
    ' @brief End primitive assembly and trigger rasterization pipeline.
    ''
    Public Sub GlEnd()
        If batchCount < 3 Then Exit Sub

        ' Compute combined MVP matrix = Projection * ModelView
        Dim mvp As GlMat4
        Mat4Multiply mvp, projectionStack(projectionDepth), modelviewStack(modelviewDepth)

        If beginMode = GL_TRIANGLES Then
            Dim i As Int32 = 0
            While (i + 2) < batchCount
                RasterizeTriangle mvp, batch(i), batch(i + 1), batch(i + 2)
                i = i + 3
            Wend
        ElseIf beginMode = GL_QUADS Then
            Dim q As Int32 = 0
            While (q + 3) < batchCount
                ' Quad v0, v1, v2, v3 -> Tri1(v0, v1, v2), Tri2(v0, v2, v3)
                RasterizeTriangle mvp, batch(q), batch(q + 1), batch(q + 2)
                RasterizeTriangle mvp, batch(q), batch(q + 2), batch(q + 3)
                q = q + 4
            Wend
        End If

        batchCount = 0
        beginMode = -1
    End Sub

End Module
