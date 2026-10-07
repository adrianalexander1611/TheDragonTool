<#
    TheDragonTool.ps1  (version con interfaz grafica)
    -----------------------------------------------------
    Creado por Adrian Barrientos
    Requiere: Windows 10/11, PowerShell 5.1+
    Recomendado: ejecutar como Administrador para que todas las funciones trabajen.

    Coloca este archivo junto a "logo.png" (mismo folder) para que el logo se muestre.

    Como ejecutarlo:
      1. Clic derecho > "Ejecutar con PowerShell" (idealmente como administrador), o
      2. En PowerShell (como administrador):
         Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
         .\TheDragonTool.ps1
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName WindowsFormsIntegration
Add-Type -AssemblyName System.Drawing

# PowerShell 5.1 puede usar TLS antiguo por defecto y las descargas (NuGet, GitHub, Microsoft) fallan: se fuerza TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$Script:Autor = "Adrian Barrientos"
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Script:ScriptDir) { $Script:ScriptDir = (Get-Location).Path }

# ---------------------------------------------------------------------------
#  UTILIDADES BASE
# ---------------------------------------------------------------------------

function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Cierra la ventana actual y vuelve a abrir el programa pidiendo elevacion a
# Administrador (funciona tanto si se ejecuta como script .ps1 con
# powershell/pwsh, como si se ejecuta como el .exe generado con ps2exe).
function Accion-AbrirComoAdministrador {
    if (Test-Admin) { return }
    $confirmar = Show-Confirm "Se va a cerrar esta ventana y The Dragon Tool se abrira de nuevo como Administrador (Windows te pedira confirmacion). Continuar?" "Abrir como administrador"
    if (-not $confirmar) { return }
    try {
        $rutaProceso = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $nombreProceso = [System.IO.Path]::GetFileName($rutaProceso)
        if ($nombreProceso -match '(?i)^(powershell|pwsh)\.exe$') {
            $rutaScript = $PSCommandPath
            if (-not $rutaScript) { $rutaScript = $MyInvocation.MyCommand.Path }
            if (-not $rutaScript) { $rutaScript = Join-Path $Script:ScriptDir "TheDragonTool.ps1" }
            Start-Process -FilePath $rutaProceso -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$rutaScript`"") -Verb RunAs -ErrorAction Stop
        } else {
            Start-Process -FilePath $rutaProceso -Verb RunAs -ErrorAction Stop
        }
        $window.Close()
    } catch {
        if ($_.Exception.Message -match '(?i)cancel') {
            Write-Log "Se cancelo la elevacion a administrador." -Tipo AVISO
        } else {
            Write-Log "No se pudo reabrir como administrador: $($_.Exception.Message)" -Tipo ERROR
            Show-Aviso "No se pudo reabrir el programa como administrador: $($_.Exception.Message)" "Error"
        }
    }
}

# Permite que la ventana WPF siga "respirando" (repintando el log) durante
# operaciones largas que corren de forma sincrona.
function Global:Wait-UI {
    param([int]$Milisegundos = 1)
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($Milisegundos)
    $timer.Add_Tick({ $frame.Continue = $false; $timer.Stop() })
    $timer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

# Recursos XAML compartidos por TODAS las ventanas secundarias (dialogos, progreso,
# pruebas...): el mismo boton redondeado/semitransparente con borde neon del panel
# lateral y una barra de progreso animada. Cada ventana los inserta dentro de su
# <Window.Resources>. Es una variable GLOBAL (y no $Script:) para que tambien se
# vea desde funciones llamadas a traves de closures.
$Global:RecursosNeonXaml = @'
    <LinearGradientBrush x:Key="NeonBrush" StartPoint="0,0" EndPoint="0.5,0.5" SpreadMethod="Repeat">
      <LinearGradientBrush.RelativeTransform>
        <TranslateTransform X="0" Y="0"/>
      </LinearGradientBrush.RelativeTransform>
      <GradientStop Color="#1F6BFF" Offset="0"/>
      <GradientStop Color="#4FA8FF" Offset="0.25"/>
      <GradientStop Color="#FFFFFF" Offset="0.5"/>
      <GradientStop Color="#4FA8FF" Offset="0.75"/>
      <GradientStop Color="#1F6BFF" Offset="1"/>
    </LinearGradientBrush>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#EAF0FA"/>
      <Setter Property="BorderThickness" Value="1.5"/>
      <Setter Property="MinHeight" Value="36"/>
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid RenderTransformOrigin="0.5,0.5">
              <Grid.RenderTransform><ScaleTransform x:Name="Esc" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
              <Border x:Name="Halo" Margin="3" CornerRadius="14" Background="#00B7FF" Opacity="0.2">
                <Border.Effect>
                  <BlurEffect Radius="10"/>
                </Border.Effect>
              </Border>
              <Border x:Name="Bd" Background="#33141C30" BorderBrush="{DynamicResource NeonBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14" SnapsToDevicePixels="True">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}" RecognizesAccessKey="False"/>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#552F7CF6"/>
                <Setter TargetName="Halo" Property="Opacity" Value="0.65"/>
                <Trigger.EnterActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="1.035" Duration="0:0:0.12"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="1.035" Duration="0:0:0.12"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.15"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.15"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#5500E5FF"/>
                <Setter TargetName="Halo" Property="Opacity" Value="0.9"/>
                <Trigger.EnterActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="0.95" Duration="0:0:0.07"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="0.95" Duration="0:0:0.07"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="1.035" Duration="0:0:0.12"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="1.035" Duration="0:0:0.12"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
                <Setter TargetName="Halo" Property="Opacity" Value="0.05"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="24"/>
      <Setter Property="Minimum" Value="0"/>
      <Setter Property="Maximum" Value="100"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="Aura" Margin="3,2" CornerRadius="12" Background="#00B7FF" Opacity="0.3">
                <Border.Effect>
                  <BlurEffect Radius="12"/>
                </Border.Effect>
              </Border>
              <Border x:Name="PART_Track" CornerRadius="12" Background="#33141C30"/>
              <Border x:Name="PART_Indicator" HorizontalAlignment="Left" CornerRadius="12" ClipToBounds="True">
                <Border.Background>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                    <GradientStop Color="#00B7FF" Offset="0"/>
                    <GradientStop Color="#2F7CF6" Offset="0.55"/>
                    <GradientStop Color="#CFE8FF" Offset="1"/>
                  </LinearGradientBrush>
                </Border.Background>
                <Grid>
                  <Rectangle x:Name="Brillo" Width="90" HorizontalAlignment="Left" IsHitTestVisible="False">
                    <Rectangle.Fill>
                      <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                        <GradientStop Color="#00FFFFFF" Offset="0"/>
                        <GradientStop Color="#99FFFFFF" Offset="0.5"/>
                        <GradientStop Color="#00FFFFFF" Offset="1"/>
                      </LinearGradientBrush>
                    </Rectangle.Fill>
                    <Rectangle.RenderTransform>
                      <TranslateTransform X="-100"/>
                    </Rectangle.RenderTransform>
                  </Rectangle>
                  <Border VerticalAlignment="Top" Height="8" CornerRadius="12,12,0,0" Background="#33FFFFFF" IsHitTestVisible="False"/>
                </Grid>
              </Border>
              <Border CornerRadius="12" BorderThickness="1.5" BorderBrush="{DynamicResource NeonBrush}" IsHitTestVisible="False"/>
              <TextBlock HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="White" FontWeight="Bold" FontSize="12"
                         Text="{Binding Value, RelativeSource={RelativeSource TemplatedParent}, StringFormat={}{0:0}%}"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="11"/>
      <Setter Property="Height" Value="Auto"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Border Background="#22000000" CornerRadius="5" Margin="1">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="Pulgar" CornerRadius="5" Background="#8800B7FF" BorderBrush="{DynamicResource NeonBrush}" BorderThickness="1"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Pulgar" Property="Background" Value="#CC00E5FF"/>
                          </Trigger>
                          <Trigger Property="IsDragging" Value="True">
                            <Setter TargetName="Pulgar" Property="Background" Value="#FFBFE3FF"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="Height" Value="11"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Border Background="#22000000" CornerRadius="5" Margin="1">
                  <Track x:Name="PART_Track">
                    <Track.DecreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageLeftCommand" Opacity="0" Focusable="False"/>
                    </Track.DecreaseRepeatButton>
                    <Track.IncreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageRightCommand" Opacity="0" Focusable="False"/>
                    </Track.IncreaseRepeatButton>
                    <Track.Thumb>
                      <Thumb>
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border x:Name="Pulgar" CornerRadius="5" Background="#8800B7FF" BorderBrush="{DynamicResource NeonBrush}" BorderThickness="1"/>
                            <ControlTemplate.Triggers>
                              <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Pulgar" Property="Background" Value="#CC00E5FF"/>
                              </Trigger>
                              <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="Pulgar" Property="Background" Value="#FFBFE3FF"/>
                              </Trigger>
                            </ControlTemplate.Triggers>
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                  </Track>
                </Border>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#99151B27"/>
      <Setter Property="Foreground" Value="#EAF0FA"/>
      <Setter Property="BorderBrush" Value="#44509BFF"/>
      <Setter Property="BorderThickness" Value="1.5"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="CaretBrush" Value="#5B9CFF"/>
      <Setter Property="SelectionBrush" Value="#552F7CF6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" CornerRadius="10" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" SnapsToDevicePixels="True">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" Focusable="False"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource NeonBrush}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
'@

# Estilos de DataGrid oscuros para las ventanas con listas (cabecera, celdas y fila elegida).
$Global:RecursosGridXaml = @'
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#151B27"/>
      <Setter Property="Foreground" Value="#66AEFF"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="BorderBrush" Value="#232B3D"/>
      <Setter Property="BorderThickness" Value="0,0,1,1"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Foreground" Value="#EAF0FA"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#2F7CF6"/>
          <Setter Property="Foreground" Value="White"/>
        </Trigger>
      </Style.Triggers>
    </Style>
'@

# Hace "correr" el degradado del pincel neon: el patron de colores se repite y se desplaza
# sin parar, asi los colores fluyen alrededor de todos los bordes (una sola animacion mueve
# todos los bordes a la vez). -Detener la congela. Devuelve $false si no se pudo animar.
function Global:Animar-PincelNeon {
    param($Pincel, [switch]$Detener)
    if (-not $Pincel) { return $false }
    try {
        $mov = $Pincel.RelativeTransform
        if ($Detener) {
            $mov.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
            $mov.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
            return $true
        }
        foreach ($propiedad in @([System.Windows.Media.TranslateTransform]::XProperty, [System.Windows.Media.TranslateTransform]::YProperty)) {
            $flujo = New-Object System.Windows.Media.Animation.DoubleAnimation
            $flujo.From = 0
            $flujo.To = 0.5
            $flujo.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(2500))
            $flujo.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $mov.BeginAnimation($propiedad, $flujo)
        }
        return $true
    } catch { return $false }
}

# Animaciones de entrada reutilizables ---------------------------------------------------

# Hace aparecer una lista de elementos uno tras otro (fundido + deslizamiento), con un pequeño retraso entre cada uno.
function Global:Animar-EntradaElementos {
    param($Elementos, [double]$DesdeX = 0, [double]$DesdeY = 0, [int]$PasoMs = 40, [int]$DuracionMs = 340)
    $i = 0
    $suave = New-Object System.Windows.Media.Animation.CubicEase
    $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    foreach ($el in @($Elementos)) {
        if (-not ($el -is [System.Windows.UIElement])) { continue }
        try {
            $espera = [TimeSpan]::FromMilliseconds($i * $PasoMs)
            if ($DesdeX -ne 0 -or $DesdeY -ne 0) {
                $mov = $el.RenderTransform -as [System.Windows.Media.TranslateTransform]
                if (-not $mov -and ($el.RenderTransform -eq $null -or $el.RenderTransform -eq [System.Windows.Media.Transform]::Identity)) {
                    $mov = New-Object System.Windows.Media.TranslateTransform
                    $el.RenderTransform = $mov
                }
                if ($mov) {
                    if ($DesdeX -ne 0) {
                        $ax = New-Object System.Windows.Media.Animation.DoubleAnimation
                        $ax.From = $DesdeX; $ax.To = 0
                        $ax.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($DuracionMs))
                        $ax.BeginTime = $espera; $ax.EasingFunction = $suave
                        $ax.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
                        $mov.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $ax)
                    }
                    if ($DesdeY -ne 0) {
                        $ay = New-Object System.Windows.Media.Animation.DoubleAnimation
                        $ay.From = $DesdeY; $ay.To = 0
                        $ay.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($DuracionMs))
                        $ay.BeginTime = $espera; $ay.EasingFunction = $suave
                        $ay.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
                        $mov.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $ay)
                    }
                }
            }
            $el.Opacity = 0
            $ao = New-Object System.Windows.Media.Animation.DoubleAnimation
            $ao.From = 0; $ao.To = 1
            $ao.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($DuracionMs))
            $ao.BeginTime = $espera
            $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $ao)
        } catch { }
        $i++
    }
}

# Al mostrarse un panel (cambio de seccion): el panel se desvanece hacia arriba y sus hijos entran en cascada.
function Global:Animar-EntradaPanel {
    param($Panel)
    if (-not $Panel) { return }
    try {
        $mov = $Panel.RenderTransform -as [System.Windows.Media.TranslateTransform]
        if (-not $mov) { $mov = New-Object System.Windows.Media.TranslateTransform; $Panel.RenderTransform = $mov }
        $suave = New-Object System.Windows.Media.Animation.CubicEase
        $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $ay = New-Object System.Windows.Media.Animation.DoubleAnimation
        $ay.From = 22; $ay.To = 0
        $ay.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(380))
        $ay.EasingFunction = $suave
        $ay.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $mov.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $ay)
        $ao = New-Object System.Windows.Media.Animation.DoubleAnimation
        $ao.From = 0; $ao.To = 1
        $ao.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(320))
        $ao.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $Panel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $ao)
        if ($Panel -is [System.Windows.Controls.Panel] -and $Panel.Children.Count -gt 1 -and $Panel.Children.Count -le 14) {
            Animar-EntradaElementos -Elementos $Panel.Children -DesdeY 18 -PasoMs 45 -DuracionMs 360
        }
    } catch { }
}

# Engancha la animacion de entrada a todos los paneles de seccion (los llamados Panel*) de una ventana.
function Global:Registrar-AnimacionesPaneles {
    param($Raiz)
    if (-not $Raiz) { return }
    $pila = New-Object 'System.Collections.Generic.Stack[object]'
    $pila.Push($Raiz)
    $enganchados = 0
    while ($pila.Count -gt 0) {
        $nodo = $pila.Pop()
        if ($nodo -is [System.Windows.Controls.Panel] -and $nodo.Name -and $nodo.Name -match '^Panel' -and $nodo.Name -notmatch 'Teclado|Checklist|Lateral') {
            $nodo.Add_IsVisibleChanged({
                param($remitente, $evento)
                if ($evento.NewValue -eq $true) { Animar-EntradaPanel -Panel $remitente }
            })
            $enganchados++
        }
        if ($nodo -is [System.Windows.DependencyObject]) {
            foreach ($hijo in [System.Windows.LogicalTreeHelper]::GetChildren($nodo)) {
                if ($hijo -is [System.Windows.DependencyObject]) { $pila.Push($hijo) }
            }
        }
    }
    return $enganchados
}

# Cambio de pestaña: el contenido sube suavemente y el titulo de la seccion entra desde la izquierda.
function Global:Animar-CambioPestana {
    try {
        $tc = $window.FindName("TabControlPrincipal")
        $titulo = $window.FindName("TxtSeccionActual")
        if ($tc) { Animar-EntradaPanel -Panel $tc }
        if ($titulo) { Animar-EntradaElementos -Elementos @($titulo) -DesdeX -26 -PasoMs 0 -DuracionMs 360 }
    } catch { }
}

# Latido suave continuo (por ejemplo el logo).
function Global:Animar-Respiracion {
    param($Elemento, [double]$Escala = 1.07, [double]$Segundos = 2.2)
    if (-not $Elemento) { return }
    try {
        $esc = New-Object System.Windows.Media.ScaleTransform(1, 1)
        $Elemento.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
        $Elemento.RenderTransform = $esc
        $suave = New-Object System.Windows.Media.Animation.SineEase
        $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
        foreach ($eje in @([System.Windows.Media.ScaleTransform]::ScaleXProperty, [System.Windows.Media.ScaleTransform]::ScaleYProperty)) {
            $latido = New-Object System.Windows.Media.Animation.DoubleAnimation
            $latido.From = 1; $latido.To = $Escala
            $latido.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($Segundos))
            $latido.AutoReverse = $true
            $latido.EasingFunction = $suave
            $latido.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $esc.BeginAnimation($eje, $latido)
        }
    } catch { }
}

# Envuelve una ventana (todavia no mostrada) en un marco neon animado y translucido:
# borde de color que gira, halo suave, "aurora" de luces que se mueven detras del contenido
# y una barra de titulo propia (con minimizar/maximizar/cerrar en la ventana principal).
# Todo va dentro de try/catch con marcha atras: si algo falla, la ventana queda como estaba.
function Global:Aplicar-MarcoNeon {
    param($Ventana, [switch]$Principal)
    if (-not $Ventana) { return }
    if ($Ventana.IsVisible -or $Ventana.IsLoaded) { return }
    if (-not $Ventana.Resources.Contains("NeonBrush")) { return }
    $contenidoOriginal = $Ventana.Content
    if (-not $contenidoOriginal) { return }
    $estiloOriginal = $Ventana.WindowStyle
    try {
        $permiteRedim = ($Ventana.ResizeMode -eq [System.Windows.ResizeMode]::CanResize -or $Ventana.ResizeMode -eq [System.Windows.ResizeMode]::CanResizeWithGrip)
        $botonesPrincipal = if ($Principal) { "Visible" } else { "Collapsed" }
        $textoTitulo = [System.Security.SecurityElement]::Escape([string]$Ventana.Title)
        $xamlMarco = @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="#01000000">
  <Grid.Resources>
    <Style x:Key="BotonBarraNeon" TargetType="Button">
      <Setter Property="Width" Value="38"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="Margin" Value="3,0,0,0"/>
      <Setter Property="Foreground" Value="#CFE3FF"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Fondo" CornerRadius="9" Background="#22FFFFFF" BorderBrush="#4400E5FF" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Fondo" Property="Background" Value="#6600B7FF"/>
                <Setter TargetName="Fondo" Property="BorderBrush" Value="#FF00E5FF"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Fondo" Property="Background" Value="#AA00E5FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BotonCerrarNeon" TargetType="Button" BasedOn="{StaticResource BotonBarraNeon}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Fondo" CornerRadius="9" Background="#22FFFFFF" BorderBrush="#44FFFFFF" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Fondo" Property="Background" Value="#CCFF2B5E"/>
                <Setter TargetName="Fondo" Property="BorderBrush" Value="#FFFF6A8A"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Fondo" Property="Background" Value="#FFFF1744"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Grid.Resources>
  <Border x:Name="MnHalo3" Margin="1" CornerRadius="24" BorderThickness="3" BorderBrush="#1200B7FF" IsHitTestVisible="False"/>
  <Border x:Name="MnHalo2" Margin="4" CornerRadius="21" BorderThickness="3" BorderBrush="#2200B7FF" IsHitTestVisible="False"/>
  <Border x:Name="MnHalo1" Margin="7" CornerRadius="19" BorderThickness="3" BorderBrush="#3A9CD0FF" IsHitTestVisible="False"/>
  <Border x:Name="MnMarco" Margin="10" CornerRadius="18" BorderThickness="2.5">
    <Border.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#EA080C16" Offset="0"/>
        <GradientStop Color="#E80D1224" Offset="0.55"/>
        <GradientStop Color="#EA120A24" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Grid x:Name="MnInterior">
      <Grid x:Name="MnAurora" ClipToBounds="True" IsHitTestVisible="False">
        <Ellipse x:Name="MnLuzA" Width="460" Height="460" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="-120,-140,0,0">
          <Ellipse.Fill>
            <RadialGradientBrush>
              <GradientStop Color="#3300E5FF" Offset="0"/>
              <GradientStop Color="#0000E5FF" Offset="1"/>
            </RadialGradientBrush>
          </Ellipse.Fill>
          <Ellipse.RenderTransform><TranslateTransform x:Name="MnMoverA"/></Ellipse.RenderTransform>
        </Ellipse>
        <Ellipse x:Name="MnLuzB" Width="520" Height="520" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,-160,-180">
          <Ellipse.Fill>
            <RadialGradientBrush>
              <GradientStop Color="#33DDEEFF" Offset="0"/>
              <GradientStop Color="#00DDEEFF" Offset="1"/>
            </RadialGradientBrush>
          </Ellipse.Fill>
          <Ellipse.RenderTransform><TranslateTransform x:Name="MnMoverB"/></Ellipse.RenderTransform>
        </Ellipse>
        <Ellipse x:Name="MnLuzC" Width="340" Height="340" HorizontalAlignment="Center" VerticalAlignment="Center">
          <Ellipse.Fill>
            <RadialGradientBrush>
              <GradientStop Color="#222F7CF6" Offset="0"/>
              <GradientStop Color="#002F7CF6" Offset="1"/>
            </RadialGradientBrush>
          </Ellipse.Fill>
          <Ellipse.RenderTransform><TranslateTransform x:Name="MnMoverC"/></Ellipse.RenderTransform>
        </Ellipse>
      </Grid>
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="40"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Margin="10,0,10,0" BorderThickness="0,0,0,1" BorderBrush="#2200E5FF">
          <Grid ClipToBounds="True">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Rectangle Grid.ColumnSpan="2" Height="2" Width="220" HorizontalAlignment="Left" VerticalAlignment="Bottom" IsHitTestVisible="False">
              <Rectangle.Fill>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#00FFFFFF" Offset="0"/>
                  <GradientStop Color="#FFFFFFFF" Offset="0.5"/>
                  <GradientStop Color="#00FFFFFF" Offset="1"/>
                </LinearGradientBrush>
              </Rectangle.Fill>
              <Rectangle.RenderTransform><TranslateTransform x:Name="MnMoverBrillo" X="-240"/></Rectangle.RenderTransform>
            </Rectangle>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="4,0,0,0">
              <Ellipse x:Name="MnPunto" Width="9" Height="9" Margin="0,0,9,0" Fill="#FF00E5FF" Opacity="0.9"/>
              <TextBlock x:Name="MnTitulo" Text="$textoTitulo" FontSize="13" FontWeight="Bold" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="MnBtnEfectos" Style="{StaticResource BotonBarraNeon}" Content="✨" ToolTip="Efectos animados: activar / desactivar (modo rendimiento)" Visibility="$botonesPrincipal"/>
              <Button x:Name="MnBtnMin" Style="{StaticResource BotonBarraNeon}" Content="&#x2014;" ToolTip="Minimizar" Visibility="$botonesPrincipal"/>
              <Button x:Name="MnBtnMax" Style="{StaticResource BotonBarraNeon}" Content="&#x25A1;" ToolTip="Maximizar / restaurar" Visibility="$botonesPrincipal"/>
              <Button x:Name="MnBtnCerrar" Style="{StaticResource BotonCerrarNeon}" Content="&#x2715;" ToolTip="Cerrar"/>
            </StackPanel>
          </Grid>
        </Border>
        <Border x:Name="MnZonaCliente" Grid.Row="1" Margin="0,0,0,2" CornerRadius="0,0,16,16"/>
      </Grid>
    </Grid>
  </Border>
</Grid>
"@
        $marco = [Windows.Markup.XamlReader]::Parse($xamlMarco)
        $borde       = $marco.FindName("MnMarco")
        $zona        = $marco.FindName("MnZonaCliente")
        $titulo      = $marco.FindName("MnTitulo")
        $btnCerrar   = $marco.FindName("MnBtnCerrar")
        $btnMin      = $marco.FindName("MnBtnMin")
        $btnMax      = $marco.FindName("MnBtnMax")
        $btnEfectos  = $marco.FindName("MnBtnEfectos")
        $halo1 = $marco.FindName("MnHalo1"); $halo2 = $marco.FindName("MnHalo2"); $halo3 = $marco.FindName("MnHalo3")
        $aurora = $marco.FindName("MnAurora")
        $punto  = $marco.FindName("MnPunto")
        $mA = $marco.FindName("MnMoverA"); $mB = $marco.FindName("MnMoverB"); $mC = $marco.FindName("MnMoverC")
        $mBrillo = $marco.FindName("MnMoverBrillo")
        if (-not ($borde -and $zona -and $titulo -and $btnCerrar -and $aurora -and $mA -and $mB -and $mC)) { throw "Faltan elementos del marco" }

        # El borde y el titulo usan el pincel neon compartido (su giro lo anima Iniciar-EfectosNeon)
        $borde.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "NeonBrush")
        $titulo.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "NeonBrush")

        # Particulas: puntitos de luz que suben lentamente por detras del contenido
        $particulas = @()
        try {
            $lienzo = New-Object System.Windows.Controls.Canvas
            $lienzo.IsHitTestVisible = $false
            $conversor = New-Object System.Windows.Media.BrushConverter
            $coloresPunto = @('#FFFFFFFF', '#FF9CD0FF', '#FFBFE3FF', '#FF4FA8FF')
            for ($k = 0; $k -lt 18; $k++) {
                $tamPunto = Get-Random -Minimum 2 -Maximum 6
                $elipse = New-Object System.Windows.Shapes.Ellipse
                $elipse.Width = $tamPunto
                $elipse.Height = $tamPunto
                $elipse.Fill = $conversor.ConvertFromString($coloresPunto[$k % 4])
                $elipse.Opacity = 0
                $elipse.IsHitTestVisible = $false
                $mueve = New-Object System.Windows.Media.TranslateTransform
                $elipse.RenderTransform = $mueve
                [System.Windows.Controls.Canvas]::SetLeft($elipse, [double](Get-Random -Minimum 0 -Maximum 1100))
                [System.Windows.Controls.Canvas]::SetTop($elipse, [double](Get-Random -Minimum 250 -Maximum 900))
                [void]$lienzo.Children.Add($elipse)
                $particulas += ,@{ Tr = $mueve; El = $elipse; Dur = (Get-Random -Minimum 6 -Maximum 13); Alt = (Get-Random -Minimum 160 -Maximum 380) }
            }
            [void]$aurora.Children.Add($lienzo)
        } catch { $particulas = @() }

        # Aurora: tres luces suaves que flotan lentamente (animaciones independientes del hilo de la interfaz)
        $estadoFx = @{ Activo = $true }
        $arrancarAurora = {
            param($mover, $dx, $dy, $segX, $segY)
            $suave = New-Object System.Windows.Media.Animation.SineEase
            $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
            $ax = New-Object System.Windows.Media.Animation.DoubleAnimation
            $ax.From = -$dx; $ax.To = $dx
            $ax.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($segX))
            $ax.AutoReverse = $true
            $ax.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $ax.EasingFunction = $suave
            $ay = New-Object System.Windows.Media.Animation.DoubleAnimation
            $ay.From = -$dy; $ay.To = $dy
            $ay.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($segY))
            $ay.AutoReverse = $true
            $ay.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $ay.EasingFunction = $suave
            $mover.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $ax)
            $mover.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $ay)
        }.GetNewClosure()
        $iniciarFx = {
            & $arrancarAurora $mA 170 90 7 9
            & $arrancarAurora $mB -190 -110 9 6
            & $arrancarAurora $mC 140 120 11 8
            if ($punto) {
                $latido = New-Object System.Windows.Media.Animation.DoubleAnimation
                $latido.From = 0.35; $latido.To = 1
                $latido.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(800))
                $latido.AutoReverse = $true
                $latido.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                $punto.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $latido)
            }
            # Brillo que recorre la barra de titulo
            if ($mBrillo) {
                $barrido = New-Object System.Windows.Media.Animation.DoubleAnimation
                $barrido.From = -240; $barrido.To = 1500
                $barrido.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(3400))
                $barrido.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                $mBrillo.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $barrido)
            }
            # Particulas que suben y se desvanecen
            foreach ($pt in $particulas) {
                $sube = New-Object System.Windows.Media.Animation.DoubleAnimation
                $sube.From = 0; $sube.To = -$pt.Alt
                $sube.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($pt.Dur))
                $sube.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                $pt.Tr.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $sube)
                $brilla = New-Object System.Windows.Media.Animation.DoubleAnimation
                $brilla.From = 0; $brilla.To = 0.85
                $brilla.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($pt.Dur / 2.0))
                $brilla.AutoReverse = $true
                $brilla.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                $pt.El.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $brilla)
            }
            # Respiracion del halo exterior
            foreach ($h in @($halo1, $halo2, $halo3)) {
                if ($h) {
                    $resp = New-Object System.Windows.Media.Animation.DoubleAnimation
                    $resp.From = 0.45; $resp.To = 1
                    $resp.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1600))
                    $resp.AutoReverse = $true
                    $resp.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                    $h.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $resp)
                }
            }
        }.GetNewClosure()
        $detenerFx = {
            foreach ($m in @($mA, $mB, $mC)) {
                $m.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
                $m.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
            }
            if ($punto) { $punto.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null) }
            if ($mBrillo) { $mBrillo.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null) }
            foreach ($pt in $particulas) {
                $pt.Tr.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
                $pt.El.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
                $pt.El.Opacity = 0
            }
            foreach ($h in @($halo1, $halo2, $halo3)) { if ($h) { $h.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null) } }
        }.GetNewClosure()
        $tierBajo = $false
        try { $tierBajo = ((([int][System.Windows.Media.RenderCapability]::Tier) -shr 16) -eq 0) } catch { }
        if ($tierBajo) {
            $estadoFx.Activo = $false
            $aurora.Visibility = 'Collapsed'
        } else {
            & $iniciarFx
        }

        # Mover el contenido original dentro del marco (los nombres siguen resolviendose con FindName)
        $Ventana.Content = $null
        $zona.Child = $contenidoOriginal
        $Ventana.Content = $marco

        # Ventana sin marco de Windows, translucida, con redimensionado conservado via WindowChrome
        $ventanaWpf = $Ventana
        $Ventana.WindowStyle = [System.Windows.WindowStyle]::None
        $Ventana.AllowsTransparency = $true
        $Ventana.Background = [System.Windows.Media.Brushes]::Transparent
        $cromo = New-Object System.Windows.Shell.WindowChrome
        $cromo.CaptionHeight = 50
        $cromo.GlassFrameThickness = [System.Windows.Thickness]::new(0)
        $cromo.CornerRadius = [System.Windows.CornerRadius]::new(0)
        $cromo.UseAeroCaptionButtons = $false
        $grosor = if ($permiteRedim) { 7 } else { 0 }
        $cromo.ResizeBorderThickness = [System.Windows.Thickness]::new($grosor)
        [System.Windows.Shell.WindowChrome]::SetWindowChrome($Ventana, $cromo)
        foreach ($b in @($btnCerrar, $btnMin, $btnMax, $btnEfectos)) {
            if ($b) { [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($b, $true) }
        }

        # El marco ocupa espacio extra: se agranda el tamaño de las ventanas de tamaño fijo
        if ($Ventana.SizeToContent -eq [System.Windows.SizeToContent]::Manual) {
            if (-not [double]::IsNaN($Ventana.Height)) { $Ventana.Height = $Ventana.Height + 64 }
            if (-not [double]::IsNaN($Ventana.Width))  { $Ventana.Width  = $Ventana.Width + 24 }
        }
        if ($Ventana.MinHeight -gt 0) { $Ventana.MinHeight = $Ventana.MinHeight + 64 }
        if ($Ventana.MinWidth -gt 0)  { $Ventana.MinWidth  = $Ventana.MinWidth + 24 }

        # Entrada animada: la ventana aparece con un fundido y un pequeño "rebote" de escala
        try {
            $escalaEntrada = New-Object System.Windows.Media.ScaleTransform(0.94, 0.94)
            $borde.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
            $borde.RenderTransform = $escalaEntrada
            $marco.Opacity = 0
            $Ventana.Add_Loaded({
                try {
                    $rebote = New-Object System.Windows.Media.Animation.BackEase
                    $rebote.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
                    $rebote.Amplitude = 0.45
                    foreach ($eje in @([System.Windows.Media.ScaleTransform]::ScaleXProperty, [System.Windows.Media.ScaleTransform]::ScaleYProperty)) {
                        $crece = New-Object System.Windows.Media.Animation.DoubleAnimation
                        $crece.From = 0.94; $crece.To = 1
                        $crece.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(520))
                        $crece.EasingFunction = $rebote
                        $escalaEntrada.BeginAnimation($eje, $crece)
                    }
                    $aparece = New-Object System.Windows.Media.Animation.DoubleAnimation
                    $aparece.From = 0; $aparece.To = 1
                    $aparece.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(380))
                    $marco.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $aparece)
                } catch { $marco.Opacity = 1 }
            }.GetNewClosure())
        } catch { $marco.Opacity = 1 }

        $btnCerrar.Add_Click({ try { $ventanaWpf.Close() } catch { } }.GetNewClosure())
        if ($btnMin) { $btnMin.Add_Click({ try { $ventanaWpf.WindowState = [System.Windows.WindowState]::Minimized } catch { } }.GetNewClosure()) }
        if ($btnMax) {
            $btnMax.Add_Click({
                try {
                    if ($ventanaWpf.WindowState -eq [System.Windows.WindowState]::Maximized) { $ventanaWpf.WindowState = [System.Windows.WindowState]::Normal }
                    else { $ventanaWpf.WindowState = [System.Windows.WindowState]::Maximized }
                } catch { }
            }.GetNewClosure())
        }
        if ($btnEfectos) {
            $btnEfectos.Add_Click({
                try {
                    $pincelNeon = $ventanaWpf.Resources["NeonBrush"]
                    if ($estadoFx.Activo) {
                        $estadoFx.Activo = $false
                        & $detenerFx
                        $aurora.Visibility = 'Collapsed'
                        [void](Animar-PincelNeon -Pincel $pincelNeon -Detener)
                    } else {
                        $estadoFx.Activo = $true
                        $aurora.Visibility = 'Visible'
                        & $iniciarFx
                        [void](Animar-PincelNeon -Pincel $pincelNeon)
                    }
                } catch { }
            }.GetNewClosure())
        }

        # Maximizado: sin esquinas redondeadas ni halo (y compensando el borde invisible de Windows)
        $Ventana.Add_StateChanged({
            try {
                if ($ventanaWpf.WindowState -eq [System.Windows.WindowState]::Maximized) {
                    $m = [System.Windows.SystemParameters]::WindowResizeBorderThickness
                    $borde.Margin = [System.Windows.Thickness]::new($m.Left + 2, $m.Top + 2, $m.Right + 2, $m.Bottom + 2)
                    $borde.CornerRadius = [System.Windows.CornerRadius]::new(0)
                    foreach ($h in @($halo1, $halo2, $halo3)) { $h.Visibility = 'Collapsed' }
                    if ($btnMax) { $btnMax.Content = [string][char]0x2750 }
                } else {
                    $borde.Margin = [System.Windows.Thickness]::new(10)
                    $borde.CornerRadius = [System.Windows.CornerRadius]::new(18)
                    foreach ($h in @($halo1, $halo2, $halo3)) { $h.Visibility = 'Visible' }
                    if ($btnMax) { $btnMax.Content = [string][char]0x25A1 }
                }
            } catch { }
        }.GetNewClosure())
    } catch {
        # Marcha atras: la ventana vuelve a su aspecto normal
        try {
            $Ventana.Content = $null
            if ($zona) { $zona.Child = $null }
            $Ventana.Content = $contenidoOriginal
            $Ventana.AllowsTransparency = $false
            $Ventana.WindowStyle = $estiloOriginal
        } catch { }
    }
}

# Pone en marcha los efectos animados de una ventana recien creada: el giro del borde
# neon (un solo pincel compartido mueve todos los bordes a la vez) y, en cada barra de
# progreso, el brillo que la recorre y el pulso de su aura. Son animaciones
# "independientes" de WPF: siguen moviendose aunque el hilo de la interfaz este ocupado.
function Global:Iniciar-EfectosNeon {
    param($Ventana)
    if (-not $Ventana) { return }
    # Marco neon translucido alrededor de la ventana (se omite si ya esta visible o no usa el pincel neon)
    if (-not $Ventana.Tag -or $Ventana.Tag -isnot [string] -or $Ventana.Tag -ne 'SinMarco') { Aplicar-MarcoNeon -Ventana $Ventana }
    # Boton "Volver" estandar de todas las ventanas: simplemente cierra la ventana que lo contiene
    # (en los dialogos modales equivale a cancelar).
    try {
        $botonVolver = $Ventana.FindName("BtnVolverVentana")
        if ($botonVolver) {
            $botonVolver.Add_Click({
                param($remitente, $evento)
                try { [System.Windows.Window]::GetWindow($remitente).Close() } catch { }
            })
        }
    } catch { }
    try {
        if ($Ventana.Resources.Contains("NeonBrush")) {
            $pincel = $Ventana.Resources["NeonBrush"]
            [void](Animar-PincelNeon -Pincel $pincel)
        }
    } catch { }
    try {
        $pila = New-Object 'System.Collections.Generic.Stack[object]'
        $pila.Push($Ventana)
        while ($pila.Count -gt 0) {
            $nodo = $pila.Pop()
            if ($nodo -is [System.Windows.Controls.ProgressBar]) {
                [void]$nodo.ApplyTemplate()
                $brillo = $nodo.Template.FindName("Brillo", $nodo)
                $aura = $nodo.Template.FindName("Aura", $nodo)
                if ($brillo) {
                    $ancho = if ($nodo.ActualWidth -gt 40) { $nodo.ActualWidth } else { 480 }
                    $barrido = New-Object System.Windows.Media.Animation.DoubleAnimation
                    $barrido.From = -100
                    $barrido.To = $ancho + 100
                    $barrido.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1700))
                    $barrido.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                    $brillo.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $barrido)
                }
                if ($aura) {
                    $pulso = New-Object System.Windows.Media.Animation.DoubleAnimation
                    $pulso.From = 0.15
                    $pulso.To = 0.65
                    $pulso.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(900))
                    $pulso.AutoReverse = $true
                    $pulso.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                    $aura.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $pulso)
                }
            }
            if ($nodo -is [System.Windows.DependencyObject]) {
                foreach ($hijo in [System.Windows.LogicalTreeHelper]::GetChildren($nodo)) {
                    if ($hijo -is [System.Windows.DependencyObject]) { $pila.Push($hijo) }
                }
            }
        }
    } catch { }
}

# Ventana emergente con barra de progreso en tiempo real, usada por los
# perfiles de optimizacion, acelerar CPU, liberar RAM, etc.
function Format-Duracion {
    param([double]$Segundos)
    if ($Segundos -lt 0 -or [double]::IsNaN($Segundos) -or [double]::IsInfinity($Segundos)) { return "calculando..." }
    if ($Segundos -lt 60) { return "$([math]::Round($Segundos)) segundo(s)" }
    $minutos = [math]::Floor($Segundos / 60)
    $segRestantes = [math]::Round($Segundos % 60)
    if ($minutos -lt 60) { return "$minutos min $segRestantes seg" }
    $horas = [math]::Floor($minutos / 60)
    $minRestantes = $minutos % 60
    return "$horas h $minRestantes min"
}

function New-VentanaProgreso {
    param([string]$Titulo, [switch]$PermitirDetener)
    $visibilidadDetener = if ($PermitirDetener) { "Visible" } else { "Collapsed" }
    [xml]$xamlProg = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Titulo" Height="490" Width="540" WindowStartupLocation="CenterScreen"
        Background="#10141D" ResizeMode="NoResize" Topmost="True">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <StackPanel Margin="20">
    <Button x:Name="BtnVolverVentana" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock Text="$Titulo" Foreground="White" FontSize="16" FontWeight="Bold" Margin="0,0,0,14"/>
    <TextBlock x:Name="TxtEstadoProgreso" Text="Iniciando..." Foreground="#66AEFF" TextWrapping="Wrap" Margin="0,0,0,10"/>
    <ProgressBar x:Name="BarraProgreso" Minimum="0" Maximum="100" Height="26" Margin="0,4,0,10"/>
    <TextBlock x:Name="TxtTiempoRestante" Text="Calculando tiempo restante..." Foreground="#7C93BD" FontSize="12" Margin="0,0,0,14"/>
    <TextBox x:Name="TxtLogProgreso" IsReadOnly="True" Height="160" TextWrapping="Wrap" AcceptsReturn="True"
             Background="#070A10" Foreground="#66AEFF" FontFamily="Consolas" FontSize="11" VerticalScrollBarVisibility="Auto"/>
    <Button x:Name="BtnDetenerProgreso" Content="⏹️ Detener" Height="38" Margin="0,12,0,0" HorizontalAlignment="Right" Width="140"
            Foreground="White" Visibility="$visibilidadDetener"/>
  </StackPanel>
</Window>
"@
    $readerProg = New-Object System.Xml.XmlNodeReader $xamlProg
    $winProg = [Windows.Markup.XamlReader]::Load($readerProg)
    $winProg.Tag = $false
    $winProg.Resources.Add("HoraInicio", (Get-Date))
    if ($PermitirDetener) {
        $winProg.FindName("BtnDetenerProgreso").Add_Click({
            $winProg.Tag = $true
            $winProg.FindName("TxtEstadoProgreso").Text = "Deteniendo... (terminando el paso actual)"
        }.GetNewClosure())
    }
    Iniciar-EfectosNeon -Ventana $winProg
    $winProg.Show()
    Wait-UI -Milisegundos 1
    return $winProg
}

function Global:Update-VentanaProgreso {
    param($Ventana, [int]$Porcentaje, [string]$Estado, [string]$LogLinea = $null)
    if (-not $Ventana) { return }
    $barra = $Ventana.FindName("BarraProgreso")
    $txtEstado = $Ventana.FindName("TxtEstadoProgreso")
    $txtLog = $Ventana.FindName("TxtLogProgreso")
    $txtTiempo = $Ventana.FindName("TxtTiempoRestante")
    $pctSeguro = [math]::Min(100, [math]::Max(0, $Porcentaje))
    if ($barra) {
        # El relleno avanza con una transicion suave (en vez de dar saltos) hasta el nuevo valor.
        $desde = [double]$barra.Value
        $delta = $pctSeguro - $desde
        if ([math]::Abs($delta) -gt 1.5) {
            $pasos = [math]::Min(14, [int][math]::Ceiling([math]::Abs($delta) / 3))
            for ($paso = 1; $paso -le $pasos; $paso++) {
                $t = $paso / $pasos
                $barra.Value = $desde + ($delta * (1 - [math]::Pow(1 - $t, 2)))
                Wait-UI -Milisegundos 12
            }
        }
        $barra.Value = $pctSeguro
    }
    if ($txtEstado -and $Estado) { $txtEstado.Text = $Estado }
    if ($LogLinea -and $txtLog) { $txtLog.AppendText("$LogLinea`r`n"); $txtLog.ScrollToEnd() }

    if ($txtTiempo -and $Ventana.Resources.Contains("HoraInicio")) {
        $transcurrido = (Get-Date) - $Ventana.Resources["HoraInicio"]
        if ($pctSeguro -ge 100) {
            $txtTiempo.Text = "Completado en $(Format-Duracion $transcurrido.TotalSeconds)."
        } elseif ($pctSeguro -gt 3) {
            $totalEstimado = $transcurrido.TotalSeconds * (100.0 / $pctSeguro)
            $restante = [math]::Max(0, $totalEstimado - $transcurrido.TotalSeconds)
            $txtTiempo.Text = "Tiempo restante estimado: $(Format-Duracion $restante) (transcurrido: $(Format-Duracion $transcurrido.TotalSeconds))"
        } else {
            $txtTiempo.Text = "Calculando tiempo restante... (transcurrido: $(Format-Duracion $transcurrido.TotalSeconds))"
        }
    }
    Wait-UI -Milisegundos 1
}

function Close-VentanaProgreso {
    param($Ventana, [string]$MensajeFinal = "Completado.")
    if (-not $Ventana) { return }
    Update-VentanaProgreso -Ventana $Ventana -Porcentaje 100 -Estado $MensajeFinal
    Start-Sleep -Milliseconds 600
    try { $Ventana.Close() } catch { }
}

$Script:RegistroErrores = New-Object System.Collections.Generic.List[object]

# Clasifica el origen de un error segun el prefijo de la funcion que lo genero,
# para poder distinguir si vino de una prueba de diagnostico, una descarga,
# instalacion/desinstalacion de programas, el registro de Windows, etc.
function Global:Get-CategoriaOrigenError {
    param([string]$Origen)
    if ($Origen -match '^(Show-Prueba|Accion-Probar|Accion-DiagnosticoCompleto|Accion-VerDetallesPantalla)') { return 'Prueba de diagnostico' }
    if ($Origen -match '^(Accion-DescargarISO|Get-EnlaceDescarga|Descargar-ArchivoConProgreso|Accion-DescargarInstalarControladorFaltante|Accion-InstalarControladorDesdeArchivo)') { return 'Descarga de archivos' }
    if ($Origen -match '^(Accion-Instalar|Accion-Desinstalar|Show-VentanaProgramasInstalados|Limpiar-RastrosPrograma)') { return 'Instalar/Desinstalar programas' }
    if ($Origen -match 'Registro') { return 'Registro de Windows' }
    if ($Origen -match 'Driver|Controlador') { return 'Controladores' }
    if ($Origen -match '^Perfil-|^Accion-Acelerar|^Accion-LiberarRAM') { return 'Perfiles de optimizacion' }
    return 'Programa general'
}

function Global:Write-Log {
    param(
        [string]$Mensaje,
        [ValidateSet('INFO','OK','AVISO','ERROR')] [string]$Tipo = 'INFO'
    )
    $hora = (Get-Date).ToString('HH:mm:ss')

    if ($Tipo -eq 'ERROR' -or $Tipo -eq 'AVISO') {
        try {
            $callStack = Get-PSCallStack
            $origen = if ($callStack.Count -gt 1 -and $callStack[1].FunctionName) { $callStack[1].FunctionName } else { "Desconocido" }
            if ($origen -eq '<ScriptBlock>') { $origen = "Interfaz (evento de la ventana)" }
            $Script:RegistroErrores.Add([PSCustomObject]@{
                Hora      = $hora
                Tipo      = $Tipo
                Categoria = (Get-CategoriaOrigenError -Origen $origen)
                Origen    = $origen
                Mensaje   = $Mensaje
            }) | Out-Null
        } catch {}
    }

    if (-not $Script:LogBox) { return }
    $prefijo = switch ($Tipo) {
        'OK'    { '[OK]   ' }
        'AVISO' { '[AVISO]' }
        'ERROR' { '[ERROR]' }
        default { '[INFO] ' }
    }
    $linea = "$hora  $prefijo  $Mensaje`r`n"
    $Script:LogBox.AppendText($linea)
    $Script:LogBox.ScrollToEnd()
    Wait-UI -Milisegundos 1
}

function Global:Show-Confirm {
    param([string]$Mensaje, [string]$Titulo = "Confirmar")
    $resultado = [System.Windows.MessageBox]::Show($Mensaje, $Titulo, 'YesNo', 'Question')
    return ($resultado -eq 'Yes')
}

function Global:Show-Aviso {
    param([string]$Mensaje, [string]$Titulo = "Aviso")
    [System.Windows.MessageBox]::Show($Mensaje, $Titulo, 'OK', 'Information') | Out-Null
}

function Global:Requiere-Admin {
    if (-not (Test-Admin)) {
        Write-Log "Esta accion requiere permisos de administrador. Vuelve a abrir el programa como administrador." -Tipo AVISO
        return $false
    }
    return $true
}

# Pequeno dialogo generico con dos campos de texto (usado para memoria virtual)
function Show-DialogoMemoriaVirtual {
    param([string]$SugeridoInicial, [string]$SugeridoMaximo)

    [xml]$xamlDlg = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Configurar memoria virtual" Height="310" Width="420"
        WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <StackPanel Margin="16">
    <Button x:Name="BtnVolverVentana" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock Text="Configurar memoria virtual (archivo de paginacion)" Foreground="White" FontWeight="Bold" FontSize="14" Margin="0,0,0,10" TextWrapping="Wrap"/>
    <RadioButton x:Name="RbAuto" Content="Administrar automaticamente (recomendado)" Foreground="White" GroupName="modo" IsChecked="True" Margin="0,2"/>
    <RadioButton x:Name="RbManual" Content="Tamaño personalizado en C:" Foreground="White" GroupName="modo" Margin="0,2,0,10"/>
    <TextBlock Text="Tamaño inicial (MB):" Foreground="White"/>
    <TextBox x:Name="TxtInicial" Margin="0,2,0,8"/>
    <TextBlock Text="Tamaño maximo (MB):" Foreground="White"/>
    <TextBox x:Name="TxtMaximo" Margin="0,2,0,12"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnCancelar" Content="Cancelar" Width="90" Margin="0,0,8,0"/>
      <Button x:Name="BtnAceptar" Content="Aceptar" Width="90"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader $xamlDlg
    $dlg = [Windows.Markup.XamlReader]::Load($reader)
    Iniciar-EfectosNeon -Ventana $dlg
    $txtInicial = $dlg.FindName("TxtInicial")
    $txtMaximo  = $dlg.FindName("TxtMaximo")
    $rbAuto     = $dlg.FindName("RbAuto")
    $rbManual   = $dlg.FindName("RbManual")
    $txtInicial.Text = $SugeridoInicial
    $txtMaximo.Text  = $SugeridoMaximo

    $resultado = $null
    $dlg.FindName("BtnCancelar").Add_Click({ $dlg.DialogResult = $false })
    $dlg.FindName("BtnAceptar").Add_Click({
        $Script:_mv_modo    = if ($rbAuto.IsChecked) { 'auto' } else { 'manual' }
        $Script:_mv_inicial = $txtInicial.Text
        $Script:_mv_maximo  = $txtMaximo.Text
        $dlg.DialogResult = $true
    })
    $ok = $dlg.ShowDialog()
    if ($ok) {
        return @{ Modo = $Script:_mv_modo; Inicial = $Script:_mv_inicial; Maximo = $Script:_mv_maximo }
    }
    return $null
}

# Ventana con lista de procesos y opcion de cerrar el seleccionado
function Show-VentanaProcesos {
    [xml]$xamlProc = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Procesos que mas RAM consumen" Height="480" Width="520"
        WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <DockPanel Margin="12">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Text="Selecciona un proceso y pulsa 'Cerrar proceso' si deseas liberar RAM" Foreground="White" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
      <Button x:Name="BtnCerrarProceso" Content="Cerrar proceso" Width="140" Margin="0,0,8,0"/>
      <Button x:Name="BtnCerrarVentana" Content="Cerrar ventana" Width="120"/>
    </StackPanel>
    <DataGrid x:Name="GridProcesos" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single"
              Background="#151B27" RowBackground="#151B27" AlternatingRowBackground="#1C2635" Foreground="White"
              BorderBrush="#232B3D" HorizontalGridLinesBrush="#232B3D" VerticalGridLinesBrush="#232B3D" RowHeaderWidth="0">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Nombre" Binding="{Binding Name}" Width="2*"/>
        <DataGridTextColumn Header="PID" Binding="{Binding Id}" Width="*"/>
        <DataGridTextColumn Header="RAM (MB)" Binding="{Binding RAM_MB}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader $xamlProc
    $win = [Windows.Markup.XamlReader]::Load($reader)
    Iniciar-EfectosNeon -Ventana $win
    $grid = $win.FindName("GridProcesos")

    $datos = Get-Process | Sort-Object WS -Descending | Select-Object -First 25 Name, Id,
        @{N='RAM_MB';E={[math]::Round($_.WS/1MB,1)}}
    $grid.ItemsSource = $datos

    $win.FindName("BtnCerrarVentana").Add_Click({ $win.Close() })
    $win.FindName("BtnCerrarProceso").Add_Click({
        $sel = $grid.SelectedItem
        if (-not $sel) {
            Show-Aviso "Selecciona primero un proceso de la lista." "Sin seleccion"
            return
        }
        if (Show-Confirm "¿Cerrar el proceso '$($sel.Name)' (PID $($sel.Id))?" "Confirmar cierre") {
            try {
                Stop-Process -Id $sel.Id -Force -ErrorAction Stop
                Write-Log "Proceso '$($sel.Name)' (PID $($sel.Id)) cerrado." -Tipo OK
                $datos = Get-Process | Sort-Object WS -Descending | Select-Object -First 25 Name, Id,
                    @{N='RAM_MB';E={[math]::Round($_.WS/1MB,1)}}
                $grid.ItemsSource = $datos
            } catch {
                Write-Log "No se pudo cerrar '$($sel.Name)': $($_.Exception.Message)" -Tipo ERROR
            }
        }
    })
    $win.ShowDialog() | Out-Null
}

# ---------------------------------------------------------------------------
#  DISCO Y ALMACENAMIENTO
# ---------------------------------------------------------------------------

function Accion-LimpiarTemporales {
    Write-Log "Limpiando archivos temporales..."
    $rutas = @(
        "$env:TEMP\*",
        "$env:WINDIR\Temp\*",
        "$env:WINDIR\Prefetch\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"
    )
    $totalLiberado = 0
    foreach ($ruta in $rutas) {
        try {
            $items = Get-ChildItem -Path $ruta -Force -Recurse -ErrorAction SilentlyContinue
            $size = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($size) { $totalLiberado += $size }
            Remove-Item -Path $ruta -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    $mb = [math]::Round($totalLiberado / 1MB, 1)
    Write-Log "Archivos temporales eliminados. Espacio aproximado liberado: $mb MB" -Tipo OK
}

function Accion-VaciarPapelera {
    Write-Log "Vaciando la papelera de reciclaje..."
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Log "Papelera vaciada correctamente." -Tipo OK
    } catch {
        Write-Log "No se pudo vaciar (puede que ya este vacia)." -Tipo AVISO
    }
}

function Accion-LimpiarWindowsUpdate {
    if (-not (Requiere-Admin)) { return }
    Write-Log "Limpiando cache de Windows Update..."
    try {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Start-Service -Name bits -ErrorAction SilentlyContinue
        Write-Log "Cache de Windows Update limpiada." -Tipo OK
    } catch {
        Write-Log "Problema al limpiar la cache de Windows Update." -Tipo AVISO
    }
}

function Accion-LiberadorEspacio {
    if (-not (Show-Confirm "Se abrira la herramienta oficial de Windows (cleanmgr). ¿Continuar?")) { return }
    try {
        Start-Process cleanmgr.exe -ArgumentList "/d C:"
        Write-Log "Liberador de espacio en disco abierto." -Tipo OK
    } catch {
        Write-Log "No se pudo abrir el Liberador de espacio en disco." -Tipo AVISO
    }
}

function Accion-OptimizarUnidades {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto puede tardar varios minutos. ¿Continuar?")) { return }
    Write-Log "Optimizando unidades (TRIM en SSD / desfragmentacion en HDD)..."
    try {
        Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
            Write-Log "Optimizando unidad $($_.DriveLetter): ..."
            Optimize-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue
        }
        Write-Log "Optimizacion de unidades completada." -Tipo OK
    } catch {
        Write-Log "Problema durante la optimizacion de unidades." -Tipo AVISO
    }
}

function Accion-ProgramarChkDsk {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Se programara un analisis de C: en el proximo reinicio. ¿Continuar?")) { return }
    try {
        cmd.exe /c "echo Y | chkdsk C: /f /r" | Out-Null
        Write-Log "Analisis de disco programado para el proximo reinicio." -Tipo OK
    } catch {
        Write-Log "No se pudo programar chkdsk." -Tipo AVISO
    }
}

function Accion-StorageSense {
    if (-not (Show-Confirm "Esto activa la limpieza automatica periodica de temporales y papelera. ¿Continuar?")) { return }
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "01" -Value 1 -Type DWord
        Set-ItemProperty -Path $path -Name "04" -Value 1 -Type DWord
        Write-Log "Storage Sense activado." -Tipo OK
    } catch {
        Write-Log "No se pudo activar Storage Sense en este sistema." -Tipo AVISO
    }
}

function Accion-LimpiarMiniaturas {
    if (-not (Show-Confirm "Esto borra la cache de miniaturas de Windows (se regeneran solas al navegar carpetas). ¿Continuar?")) { return }
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
        Write-Log "Cache de miniaturas eliminada." -Tipo OK
    } catch {
        Write-Log "No se pudo limpiar la cache de miniaturas." -Tipo AVISO
    }
}

function Accion-LimpiarVolcadosMemoria {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto borra los archivos de volcado de memoria (crash dumps) generados por errores anteriores. ¿Continuar?")) { return }
    try {
        $total = 0
        $rutas = @("$env:WINDIR\Minidump\*.dmp", "$env:WINDIR\MEMORY.DMP", "$env:LOCALAPPDATA\CrashDumps\*.dmp")
        foreach ($r in $rutas) {
            $items = Get-ChildItem -Path $r -Force -ErrorAction SilentlyContinue
            $total += ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            Remove-Item -Path $r -Force -ErrorAction SilentlyContinue
        }
        $mb = [math]::Round($total / 1MB, 1)
        Write-Log "Volcados de memoria eliminados. Espacio liberado: $mb MB" -Tipo OK
    } catch {
        Write-Log "No se pudieron limpiar los volcados de memoria." -Tipo AVISO
    }
}

function Accion-LimpiezaDISM {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto ejecuta una limpieza profunda de componentes de Windows (WinSxS). Puede tardar varios minutos. ¿Continuar?")) { return }
    try {
        Write-Log "Ejecutando limpieza de componentes (DISM)... esto puede tardar." -Tipo INFO
        Start-Process -FilePath "Dism.exe" -ArgumentList "/online","/Cleanup-Image","/StartComponentCleanup" -Wait -NoNewWindow
        Write-Log "Limpieza de componentes de Windows completada." -Tipo OK
    } catch {
        Write-Log "No se pudo completar la limpieza de componentes." -Tipo ERROR
    }
}

function Accion-CarpetasPesadas {
    Write-Log "Analizando las carpetas mas pesadas de tu perfil (puede tardar unos segundos)..."
    try {
        $base = $env:USERPROFILE
        $carpetas = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue
        $resultados = foreach ($c in $carpetas) {
            $tam = (Get-ChildItem -Path $c.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            [PSCustomObject]@{ Carpeta = $c.FullName; MB = [math]::Round(($tam / 1MB), 1) }
        }
        $top = $resultados | Sort-Object MB -Descending | Select-Object -First 10
        Write-Log "Top 10 carpetas mas pesadas en $base :" -Tipo OK
        foreach ($t in $top) { Write-Log " - $($t.Carpeta): $($t.MB) MB" }
    } catch {
        Write-Log "No se pudo completar el analisis de carpetas." -Tipo AVISO
    }
}

function Accion-ResetMicrosoftStore {
    if (-not (Show-Confirm "Esto restablece la cache de Microsoft Store (soluciona errores de descarga/actualizacion de apps). ¿Continuar?")) { return }
    try {
        Start-Process "wsreset.exe"
        Write-Log "Restableciendo Microsoft Store..." -Tipo OK
    } catch {
        Write-Log "No se pudo restablecer Microsoft Store." -Tipo AVISO
    }
}

# ---------------------------------------------------------------------------
#  MEMORIA Y RENDIMIENTO
# ---------------------------------------------------------------------------

function Accion-VerProcesos {
    Show-VentanaProcesos
}

function Accion-ConfigurarMemoriaVirtual {
    if (-not (Requiere-Admin)) { return }
    $os = Get-CimInstance Win32_OperatingSystem
    $sugInicial = [math]::Round(($os.TotalVisibleMemorySize/1KB) * 1.5)
    $sugMaximo  = [math]::Round(($os.TotalVisibleMemorySize/1KB) * 3)
    $res = Show-DialogoMemoriaVirtual -SugeridoInicial $sugInicial -SugeridoMaximo $sugMaximo
    if (-not $res) { Write-Log "Configuracion de memoria virtual cancelada." -Tipo AVISO; return }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($res.Modo -eq 'auto') {
            Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile = $true} | Out-Null
            Write-Log "Memoria virtual en modo automatico. Reinicia para aplicar el cambio." -Tipo OK
        } else {
            Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile = $false} | Out-Null
            $pf = Get-CimInstance Win32_PageFileSetting -Filter "Name='C:\\pagefile.sys'" -ErrorAction SilentlyContinue
            if ($pf) {
                Set-CimInstance -InputObject $pf -Property @{InitialSize = [int]$res.Inicial; MaximumSize = [int]$res.Maximo} | Out-Null
            } else {
                New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                    Name = "C:\pagefile.sys"; InitialSize = [int]$res.Inicial; MaximumSize = [int]$res.Maximo
                } | Out-Null
            }
            Write-Log "Memoria virtual configurada: inicial $($res.Inicial) MB, maximo $($res.Maximo) MB. Reinicia para aplicar." -Tipo OK
        }
    } catch {
        Write-Log "No se pudo configurar la memoria virtual: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-EfectosVisuales {
    if (-not (Show-Confirm "Esto reduce animaciones y sombras para ganar velocidad. ¿Continuar?")) { return }
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "VisualFXSetting" -Value 2 -Type DWord
        Write-Log "Efectos visuales en modo 'mejor rendimiento'. Cierra sesion o reinicia para verlo completo." -Tipo OK
    } catch {
        Write-Log "No se pudo aplicar el cambio de efectos visuales." -Tipo AVISO
    }
}

function Accion-PlanAltoRendimiento {
    if (-not (Show-Confirm "En laptops esto aumenta el consumo de bateria a cambio de velocidad. ¿Continuar?")) { return }
    try {
        powercfg -setactive SCHEME_MIN
        Write-Log "Plan de energia cambiado a Alto rendimiento." -Tipo OK
    } catch {
        Write-Log "No se pudo cambiar el plan de energia." -Tipo AVISO
    }
}

function Accion-GestionarSysMain {
    param([string]$Modo)  # 'activar' o 'desactivar'
    if (-not (Requiere-Admin)) { return }
    $servicio = Get-Service -Name SysMain -ErrorAction SilentlyContinue
    if (-not $servicio) { Write-Log "El servicio SysMain no esta presente en este equipo." -Tipo AVISO; return }
    try {
        if ($Modo -eq 'desactivar') {
            Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue
            Set-Service -Name SysMain -StartupType Disabled
            Write-Log "SysMain (Superfetch) desactivado." -Tipo OK
        } else {
            Set-Service -Name SysMain -StartupType Automatic
            Start-Service -Name SysMain -ErrorAction SilentlyContinue
            Write-Log "SysMain (Superfetch) activado." -Tipo OK
        }
    } catch {
        Write-Log "No se pudo cambiar el estado de SysMain." -Tipo AVISO
    }
}

function Accion-RevisarInicio {
    Write-Log "Programas que inician con Windows:"
    try {
        $items = Get-CimInstance Win32_StartupCommand -ErrorAction Stop
        foreach ($i in $items) { Write-Log " - $($i.Name) | $($i.Location)" }
        if (Show-Confirm "¿Quieres abrir el Administrador de tareas en la pestaña 'Inicio' para deshabilitar alguno?") {
            Start-Process taskmgr.exe
        }
    } catch {
        Write-Log "No se pudo obtener la lista de programas de inicio." -Tipo AVISO
    }
}

function Accion-AbrirTaskManager {
    Start-Process taskmgr.exe
    Write-Log "Administrador de tareas abierto." -Tipo OK
}

function Accion-AbrirResMon {
    Start-Process resmon.exe
    Write-Log "Monitor de recursos abierto." -Tipo OK
}

function Accion-AbrirServicios {
    if (-not (Requiere-Admin)) { return }
    Start-Process services.msc
    Write-Log "Panel de Servicios de Windows abierto." -Tipo OK
}

function Accion-PriorizarPrimerPlanoBoton {
    if (-not (Show-Confirm "Esto ajusta Windows para priorizar la CPU en las aplicaciones abiertas (mas respuesta, menos 'lag'). ¿Continuar?")) { return }
    Accion-PriorizarPrimerPlano
}

function Accion-BackgroundAppsOffBoton {
    if (-not (Show-Confirm "Esto desactiva las apps que se ejecutan en segundo plano (menos uso de RAM y CPU en reposo). ¿Continuar?")) { return }
    Accion-BackgroundAppsOff
}

# ---------------------------------------------------------------------------
#  CONTROLADORES Y ACTUALIZACIONES
# ---------------------------------------------------------------------------

# --- Copia de seguridad de controladores ---
# Exporta todos los controladores de terceros (no los de Microsoft) a una
# carpeta, para poder reinstalarlos rapido si algo sale mal (reinstalacion de
# Windows, controlador dañado, etc.), sin depender de internet.
function Accion-BackupControladores {
    if (-not (Requiere-Admin)) { return }
    Add-Type -AssemblyName System.Windows.Forms
    $dialogo = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialogo.Description = "Elige donde guardar la copia de seguridad de los controladores"
    if ($dialogo.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Log "Copia de seguridad de controladores cancelada (no se eligio carpeta)." -Tipo AVISO
        return
    }
    $carpetaDestino = Join-Path $dialogo.SelectedPath "ControladoresBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if (-not (Show-Confirm "Se exportaran todos los controladores de terceros instalados a:`n$carpetaDestino`n`nPuede tardar unos minutos. ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Creando copia de seguridad de controladores"
    Update-VentanaProgreso -Ventana $prog -Porcentaje 20 -Estado "Exportando controladores..." -LogLinea "Exportando a: $carpetaDestino"
    try {
        New-Item -Path $carpetaDestino -ItemType Directory -Force | Out-Null
        $resultado = Start-Process -FilePath "dism.exe" -ArgumentList @("/online", "/export-driver", "/destination:$carpetaDestino") -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($resultado.ExitCode -eq 0) {
            $cantidad = (Get-ChildItem -Path $carpetaDestino -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue).Count
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "Copia de seguridad completada."
            Write-Log "Copia de seguridad de controladores creada en '$carpetaDestino' ($cantidad archivo(s) .inf)." -Tipo OK
            Show-Aviso "Copia de seguridad completada: $cantidad controlador(es) exportado(s) a:`n$carpetaDestino" "Copia completada"
        } else {
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "No se pudo completar."
            Write-Log "DISM no pudo exportar los controladores (codigo $($resultado.ExitCode))." -Tipo ERROR
        }
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error durante la exportacion."
        Write-Log "Error al exportar controladores: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-RestaurarControladoresBackup {
    if (-not (Requiere-Admin)) { return }
    Add-Type -AssemblyName System.Windows.Forms
    $dialogo = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialogo.Description = "Elige la carpeta con la copia de seguridad de controladores a restaurar"
    if ($dialogo.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Log "Restauracion de controladores cancelada (no se eligio carpeta)." -Tipo AVISO
        return
    }
    $carpetaOrigen = $dialogo.SelectedPath
    $cantidadInf = (Get-ChildItem -Path $carpetaOrigen -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue).Count
    if ($cantidadInf -eq 0) {
        Show-Aviso "No se encontraron archivos .inf en esa carpeta." "Carpeta vacia"
        return
    }
    if (-not (Show-Confirm "Se instalaran $cantidadInf controlador(es) desde:`n$carpetaOrigen`n`n¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Restaurando controladores"
    Update-VentanaProgreso -Ventana $prog -Porcentaje 30 -Estado "Instalando controladores desde la copia de seguridad..." -LogLinea "Instalando desde: $carpetaOrigen"
    try {
        $resultado = Start-Process -FilePath "pnputil.exe" -ArgumentList @("/add-driver", "$carpetaOrigen\*.inf", "/subdirs", "/install") -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Restauracion finalizada."
        Write-Log "Controladores restaurados desde '$carpetaOrigen' (codigo de salida $($resultado.ExitCode))." -Tipo OK
        Show-Aviso "Restauracion de controladores finalizada." "Completado"
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error durante la restauracion."
        Write-Log "Error al restaurar controladores: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-RepararControladores {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Se intentara reparar los controladores con problemas: se desactiva y reactiva cada dispositivo afectado y se le pide a Windows que vuelva a detectar el hardware. No se desinstala ningun controlador. ¿Continuar?")) { return }
    try {
        $problemas = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -ne 'OK' })
        if ($problemas.Count -eq 0) {
            Write-Log "No se detectaron controladores con problemas para reparar." -Tipo OK
            return
        }
        Write-Log "Reparando $($problemas.Count) dispositivo(s) con problemas..."
        foreach ($p in $problemas) {
            try {
                Write-Log " - Reparando: $($p.FriendlyName)..."
                Disable-PnpDevice -InstanceId $p.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Enable-PnpDevice -InstanceId $p.InstanceId -Confirm:$false -ErrorAction Stop
                Write-Log "   Dispositivo reactivado correctamente." -Tipo OK
            } catch {
                Write-Log "   No se pudo reactivar automaticamente: $($_.Exception.Message)" -Tipo AVISO
            }
        }
        try {
            Write-Log "Solicitando a Windows que vuelva a detectar el hardware..."
            Start-Process -FilePath "pnputil.exe" -ArgumentList "/scan-devices" -Wait -NoNewWindow -ErrorAction Stop
        } catch {}
        Write-Log "Reparacion finalizada. Si algun dispositivo sigue con problemas, prueba 'Actualizar controladores automaticamente' o revisalo en 'Ver todos los controladores'." -Tipo OK
    } catch {
        Write-Log "No se pudo completar la reparacion de controladores: $($_.Exception.Message)" -Tipo ERROR
    }
}

# --- Instalador universal de controladores ---
# UpdateDriverForPlugAndPlayDevices (newdev.dll) es la misma API oficial de
# Windows que usan pnputil.exe y el Administrador de dispositivos para
# instalar un controlador desde un archivo .inf. No importa de donde venga
# el .inf (Windows Update, el almacen local de controladores, una pagina del
# fabricante descargada manualmente, un USB, etc.): si es compatible con el
# ID de hardware, esta API lo instala.
$Script:TipoInstalarDriverListo = $false
function Ensure-TipoInstalarDriver {
    if ($Script:TipoInstalarDriverListo) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;

public class DragonToolDriverInstall {
    [DllImport("newdev.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool UpdateDriverForPlugAndPlayDevices(
        IntPtr hwndParent, string HardwareId, string FullInfPath, uint InstallFlags, out bool bRebootRequired);

    public static string InstalarDesdeInf(string hardwareId, string infPath) {
        bool reboot;
        bool ok = UpdateDriverForPlugAndPlayDevices(IntPtr.Zero, hardwareId, infPath, 0x00000001, out reboot);
        if (ok) { return reboot ? "OK_REBOOT" : "OK"; }
        int err = Marshal.GetLastWin32Error();
        return "ERROR_" + err;
    }
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoInstalarDriverListo = $true
}

function Accion-InstalarControladorDesdeArchivo {
    param($Item)
    if (-not $Item) { Show-Aviso "Selecciona primero un dispositivo de la lista." "Sin seleccion"; return }
    if (-not (Requiere-Admin)) { return }
    if (-not $Item.HardwareID) {
        Show-Aviso "Este dispositivo no tiene un ID de hardware disponible, no se puede instalar un controlador para el con seguridad." "Sin ID de hardware"
        return
    }
    try { Ensure-TipoInstalarDriver } catch {
        Write-Log "No se pudo preparar el instalador de controladores: $($_.Exception.Message)" -Tipo ERROR
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    $dialogo = New-Object System.Windows.Forms.OpenFileDialog
    $dialogo.Title = "Selecciona el archivo .inf del controlador para '$($Item.Nombre)'"
    $dialogo.Filter = "Archivos de instalacion de controlador (*.inf)|*.inf|Todos los archivos (*.*)|*.*"
    $resultado = $dialogo.ShowDialog()
    if ($resultado -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Log "Instalacion desde archivo cancelada (no se selecciono ningun .inf)." -Tipo AVISO
        return
    }
    $rutaInf = $dialogo.FileName

    if (-not (Show-Confirm "Se instalara el controlador de:`n$rutaInf`n`npara: $($Item.Nombre)`n`n¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Instalando controlador desde archivo"
    Update-VentanaProgreso -Ventana $prog -Porcentaje 20 -Estado "Validando compatibilidad..." -LogLinea "Archivo: $rutaInf"
    Update-VentanaProgreso -Ventana $prog -Porcentaje 55 -Estado "Instalando controlador..."
    try {
        $resultadoInstall = [DragonToolDriverInstall]::InstalarDesdeInf($Item.HardwareID, $rutaInf)
        if ($resultadoInstall -eq 'OK' -or $resultadoInstall -eq 'OK_REBOOT') {
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "Controlador instalado."
            Write-Log "Controlador instalado desde archivo para '$($Item.Nombre)'." -Tipo OK
            if ($resultadoInstall -eq 'OK_REBOOT') {
                Show-Aviso "Controlador instalado correctamente.`n`nSe requiere reiniciar el equipo para completar la instalacion." "Reinicio requerido"
            } else {
                Show-Aviso "Controlador instalado correctamente." "Listo"
            }
        } else {
            $codigoError = $resultadoInstall -replace 'ERROR_', ''
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "No se pudo instalar."
            Write-Log "No se pudo instalar el controlador (codigo de error de Windows: $codigoError). El .inf puede no ser compatible con este dispositivo." -Tipo ERROR
            Show-Aviso "No se pudo instalar el controlador (codigo de error de Windows: $codigoError).`n`nEsto suele significar que el archivo .inf no es compatible con este dispositivo especifico." "No se pudo instalar"
        }
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error durante la instalacion."
        Write-Log "Error al instalar el controlador: $($_.Exception.Message)" -Tipo ERROR
    }
}

# --- Descargar e instalar automaticamente un controlador compatible ---
# Usa el catalogo de controladores de Windows Update (Windows Update Agent /
# COM API, integrado en Windows). No requiere que el controlador venga de la
# pagina del fabricante: basta con que sea compatible con el ID de hardware
# del dispositivo y este firmado/verificado a traves de Windows Update.
function Accion-DescargarInstalarControladorFaltante {
    param($Item)
    if (-not $Item) { Show-Aviso "Selecciona un dispositivo de la lista primero." "Sin seleccion"; return }
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Se buscara un controlador compatible para '$($Item.Nombre)' a traves del catalogo de Windows Update.`n`nNo necesariamente sera de la pagina del fabricante, pero si sera un controlador compatible y verificado. Puede tardar varios minutos. ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Buscando e instalando controlador" -PermitirDetener
    Update-VentanaProgreso -Ventana $prog -Porcentaje 5 -Estado "Iniciando busqueda en el catalogo de Windows Update..." -LogLinea "Buscando controlador compatible para '$($Item.Nombre)' (ID: $($Item.HardwareID))..."

    $hwid = "$($Item.HardwareID)"
    $nombreDispositivo = "$($Item.Nombre)"

    $job = Start-Job -ScriptBlock {
        param($HardwareID, $NombreDispositivo)
        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $resultadoBusqueda = $searcher.Search("IsInstalled=0 and Type='Driver'")

            $candidatos = New-Object System.Collections.Generic.List[object]
            foreach ($u in $resultadoBusqueda.Updates) {
                $coincide = $false
                try {
                    foreach ($hw in $u.DriverHardwareID) {
                        if ($HardwareID -and "$hw" -like "*$HardwareID*") { $coincide = $true; break }
                    }
                } catch {
                    try { if ($HardwareID -and "$($u.DriverHardwareID)" -like "*$HardwareID*") { $coincide = $true } } catch {}
                }
                if (-not $coincide -and $NombreDispositivo) {
                    try { if ($u.Title -match [regex]::Escape($NombreDispositivo)) { $coincide = $true } } catch {}
                }
                if ($coincide) { $candidatos.Add($u) | Out-Null }
            }

            if ($candidatos.Count -eq 0) {
                # Respaldo: buscar en el almacen local de controladores de Windows
                # (C:\Windows\INF), por si ya existe un paquete compatible instalado
                # previamente por Windows Update o alguna otra instalacion.
                try {
                    $infCoincidente = Get-ChildItem -Path "$env:WINDIR\INF" -Filter "oem*.inf" -ErrorAction SilentlyContinue |
                        Select-String -Pattern ([regex]::Escape($HardwareID)) -SimpleMatch -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ($infCoincidente -and $HardwareID) {
                        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DragonToolDriverInstallJob {
    [DllImport("newdev.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool UpdateDriverForPlugAndPlayDevices(IntPtr hwndParent, string HardwareId, string FullInfPath, uint InstallFlags, out bool bRebootRequired);
    public static string InstalarDesdeInf(string hardwareId, string infPath) {
        bool reboot;
        bool ok = UpdateDriverForPlugAndPlayDevices(IntPtr.Zero, hardwareId, infPath, 0x00000001, out reboot);
        if (ok) { return reboot ? "OK_REBOOT" : "OK"; }
        return "ERROR_" + Marshal.GetLastWin32Error();
    }
}
"@ -ErrorAction Stop
                        $resInf = [DragonToolDriverInstallJob]::InstalarDesdeInf($HardwareID, $infCoincidente.Path)
                        if ($resInf -eq 'OK' -or $resInf -eq 'OK_REBOOT') {
                            return @{ Exito = $true; Mensaje = "Controlador encontrado en el almacen local de Windows e instalado correctamente."; RequiereReinicio = ($resInf -eq 'OK_REBOOT') }
                        }
                    }
                } catch {}
                return @{ Exito = $false; Mensaje = "No se encontro un controlador compatible ni en el catalogo de Windows Update ni en el almacen local de controladores de este equipo." }
            }

            $elegido = $candidatos[0]

            $coleccionDescarga = New-Object -ComObject Microsoft.Update.UpdateColl
            $coleccionDescarga.Add($elegido) | Out-Null
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $coleccionDescarga
            $resultDescarga = $downloader.Download()
            if ($resultDescarga.ResultCode -ne 2) {
                return @{ Exito = $false; Mensaje = "No se pudo descargar el controlador '$($elegido.Title)' (codigo $($resultDescarga.ResultCode))." }
            }

            $coleccionInstalar = New-Object -ComObject Microsoft.Update.UpdateColl
            $coleccionInstalar.Add($elegido) | Out-Null
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $coleccionInstalar
            $resultInstalar = $installer.Install()

            if ($resultInstalar.ResultCode -eq 2) {
                return @{ Exito = $true; Mensaje = "Controlador '$($elegido.Title)' instalado correctamente."; RequiereReinicio = [bool]$resultInstalar.RebootRequired }
            } else {
                return @{ Exito = $false; Mensaje = "La instalacion de '$($elegido.Title)' no se completo correctamente (codigo $($resultInstalar.ResultCode))." }
            }
        } catch {
            return @{ Exito = $false; Mensaje = "Error: $($_.Exception.Message)" }
        }
    } -ArgumentList $hwid, $nombreDispositivo

    $pct = 10
    $cancelado = $false
    while ($job.State -eq 'Running') {
        $pct = [math]::Min(92, $pct + 2)
        Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Buscando / descargando / instalando controlador compatible..."
        if ($prog.Tag -eq $true) {
            $cancelado = $true
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            break
        }
        Start-Sleep -Milliseconds 400
        Wait-UI -Milisegundos 1
    }

    if ($cancelado) {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Cancelado por el usuario."
        Write-Log "Busqueda/instalacion de controlador cancelada por el usuario." -Tipo AVISO
        return
    }

    $resultado = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    if ($resultado -and $resultado.Exito) {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Controlador instalado."
        Write-Log $resultado.Mensaje -Tipo OK
        if ($resultado.RequiereReinicio) {
            Show-Aviso "$($resultado.Mensaje)`n`nSe requiere reiniciar el equipo para completar la instalacion." "Reinicio requerido"
        } else {
            Show-Aviso $resultado.Mensaje "Controlador instalado"
        }
    } else {
        $msj = if ($resultado -and $resultado.Mensaje) { $resultado.Mensaje } else { "No se pudo completar la busqueda/instalacion del controlador." }
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Sin resultado."
        Write-Log $msj -Tipo AVISO
        Show-Aviso "$msj`n`nPuedes usar el 'Buscador de controladores' para descargarlo manualmente, y luego 'Instalar desde archivo' con el .inf que descargues." "Sin resultado"
    }
}

function Get-ControladoresFaltantes {
    # Dispositivos presentes que NO tienen controlador instalado o que tienen
    # problemas (a diferencia de Get-TodosLosControladores, que solo lista los
    # que SI tienen un driver firmado). Util para detectar "dispositivos
    # desconocidos" o hardware sin controlador en el Administrador de dispositivos.
    try {
        $pnp = Get-PnpDevice -PresentOnly -ErrorAction Stop
        $firmados = Get-CimInstance -ClassName Win32_PnPSignedDriver -Property DeviceName -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty DeviceName -ErrorAction SilentlyContinue
        $firmadosSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($firmados), [System.StringComparer]::OrdinalIgnoreCase)

        $faltantes = @($pnp | Where-Object {
            $_.Status -ne 'OK' -or -not $firmadosSet.Contains($_.FriendlyName)
        })

        if ($faltantes.Count -eq 0) { return @() }

        # Una sola consulta agrupada para todos los IDs de hardware y fabricantes,
        # en vez de una consulta por cada dispositivo (mucho mas rapido).
        $instanceIds = $faltantes | Where-Object { $_.InstanceId } | Select-Object -ExpandProperty InstanceId -Unique
        $hwidPorInstancia = @{}
        $fabricantePorInstancia = @{}
        if ($instanceIds) {
            try {
                $props = Get-PnpDeviceProperty -InstanceId $instanceIds -KeyName 'DEVPKEY_Device_HardwareIds','DEVPKEY_Device_Manufacturer' -ErrorAction SilentlyContinue
                foreach ($p in $props) {
                    if ($p.KeyName -eq 'DEVPKEY_Device_HardwareIds' -and $p.Data -and $p.Data.Count -gt 0) {
                        $hwidPorInstancia[$p.InstanceId] = $p.Data[0]
                    } elseif ($p.KeyName -eq 'DEVPKEY_Device_Manufacturer' -and $p.Data) {
                        $fabricantePorInstancia[$p.InstanceId] = $p.Data
                    }
                }
            } catch {}
        }

        $resultado = foreach ($d in $faltantes) {
            $hwid = if ($hwidPorInstancia.ContainsKey($d.InstanceId)) { $hwidPorInstancia[$d.InstanceId] } else { $null }
            $fabricante = if ($fabricantePorInstancia.ContainsKey($d.InstanceId)) { $fabricantePorInstancia[$d.InstanceId] } else { "Desconocido" }

            [PSCustomObject]@{
                Nombre        = $d.FriendlyName
                Fabricante    = $fabricante
                Clase         = $d.Class
                Version       = "N/D"
                Fecha         = "N/D"
                Estado        = $d.Status
                Recomendacion = "Instalar controlador"
                HardwareID    = $hwid
            }
        }
        return $resultado | Sort-Object Nombre
    } catch {
        Write-Log "No se pudo detectar controladores faltantes: $($_.Exception.Message)" -Tipo ERROR
        return @()
    }
}

function Get-TodosLosControladores {
    # Version rapida: solo dos consultas CIM ligeras (controladores firmados + estado de cada
    # dispositivo). Antes tambien se consultaba cada dispositivo por separado en el
    # Administrador de dispositivos para sacar el ID de hardware, que era lo que mas tardaba;
    # ahora ese dato ya viene en la misma consulta (HardWareID).
    try {
        $firmados = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -Property DeviceName,DeviceID,Manufacturer,DriverVersion,DriverDate,DeviceClass,HardWareID,InfName -ErrorAction Stop |
            Where-Object { $_.DeviceName })

        $codigoPorId = @{}
        try {
            foreach ($ent in @(Get-CimInstance -ClassName Win32_PnPEntity -Property DeviceID,ConfigManagerErrorCode -ErrorAction Stop)) {
                if ($ent.DeviceID) { $codigoPorId["$($ent.DeviceID)"] = [int]$ent.ConfigManagerErrorCode }
            }
        } catch {}

        $ahora = Get-Date
        $resultado = foreach ($d in $firmados) {
            $codigo = 0
            if ($d.DeviceID -and $codigoPorId.ContainsKey("$($d.DeviceID)")) { $codigo = $codigoPorId["$($d.DeviceID)"] }
            $estado = if ($codigo -eq 0) { 'OK' } elseif ($codigo -eq 22) { 'Deshabilitado' } else { 'Error' }

            $fecha = $null
            if ($d.DriverDate) {
                if ($d.DriverDate -is [datetime]) { $fecha = $d.DriverDate }
                else { try { $fecha = [Management.ManagementDateTimeConverter]::ToDateTime($d.DriverDate) } catch { try { $fecha = [datetime]$d.DriverDate } catch {} } }
            }
            $antiguedadAnios = if ($fecha) { [math]::Round(($ahora - $fecha).Days / 365, 1) } else { $null }

            $recomendacion =
                if ($codigo -eq 22) { "Dispositivo deshabilitado (activalo en el Administrador de dispositivos)" }
                elseif ($estado -ne 'OK') { "Instalar / reparar controlador" }
                elseif ($antiguedadAnios -and $antiguedadAnios -gt 2) { "Revisar actualizacion (controlador de hace $antiguedadAnios anios)" }
                else { "Al dia" }

            $hwid = if ($d.HardWareID) { "$($d.HardWareID)" } else { "$($d.DeviceID)" }

            [PSCustomObject]@{
                Nombre        = $d.DeviceName
                Fabricante    = $d.Manufacturer
                Clase         = $d.DeviceClass
                Version       = $d.DriverVersion
                Fecha         = if ($fecha) { $fecha.ToString('yyyy-MM-dd') } else { "Desconocida" }
                Estado        = $estado
                Recomendacion = $recomendacion
                HardwareID    = $hwid
                InstanceId    = "$($d.DeviceID)"
            }
        }
        return $resultado | Sort-Object @{Expression = { $_.Recomendacion -ne 'Al dia' }; Descending = $true }, Nombre
    } catch {
        Write-Log "No se pudo obtener la lista de controladores: $($_.Exception.Message)" -Tipo ERROR
        return @()
    }
}


function Accion-EliminarControlador {
    # Devuelve $true si el controlador se elimino, $false en cualquier otro caso.
    param($Item, $Grid)
    if (-not (Requiere-Admin)) { return $false }
    if (-not (Show-Confirm "¿Eliminar por completo el controlador de '$($Item.Nombre)'?`n`nEl dispositivo puede dejar de funcionar hasta que instales un controlador de nuevo (Windows suele reinstalar uno generico automaticamente). ¿Continuar?")) { return $false }
    try {
        $idDispositivo = $null
        if ($Item.InstanceId) { $idDispositivo = "$($Item.InstanceId)" }
        if (-not $idDispositivo) {
            $dispositivo = Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.FriendlyName -eq $Item.Nombre } | Select-Object -First 1
            if ($dispositivo) { $idDispositivo = "$($dispositivo.InstanceId)" }
        }
        if (-not $idDispositivo) { Write-Log "No se encontro el dispositivo para eliminar su controlador." -Tipo AVISO; return $false }
        Start-Process -FilePath "pnputil.exe" -ArgumentList "/remove-device", "`"$idDispositivo`"" -Wait -NoNewWindow
        Write-Log "Controlador de '$($Item.Nombre)' eliminado." -Tipo OK
        if ($Grid) { $Grid.ItemsSource = Get-TodosLosControladores }
        return $true
    } catch {
        Write-Log "No se pudo eliminar el controlador: $($_.Exception.Message)" -Tipo ERROR
        return $false
    }
}

# ---------------------------------------------------------------------------
#  CONTROLADORES OBSOLETOS O NO COMPATIBLES: buscar, elegir y borrar
# ---------------------------------------------------------------------------
# Busca tres clases de "basura" de controladores y deja que el usuario marque
# cuales quiere eliminar:
#   - No compatible: dispositivos conectados cuyo controlador da error de carga,
#     esta bloqueado por Windows o no tiene firma valida (codigos 10, 31, 37, 39,
#     43, 48 y 52 del Administrador de dispositivos).
#   - Version anterior: paquetes de terceros del almacen de controladores que ya
#     tienen una version mas nueva instalada y que ningun dispositivo usa.
#   - Sin uso: paquetes de terceros que ningun dispositivo conectado utiliza.
#   - No conectado: dispositivos "fantasma" que estuvieron conectados y ya no.
# Nunca se tocan los controladores propios de Windows (Inbox) ni los criticos de
# arranque, y los paquetes en uso se borran SIN forzar (si siguen en uso, Windows
# se niega y se conservan).

function Get-ControladoresObsoletos {
    param($Progreso = $null)
    $lista = New-Object System.Collections.Generic.List[object]

    if ($Progreso) { Update-VentanaProgreso -Ventana $Progreso -Porcentaje 8 -Estado "Leyendo los controladores que usan tus dispositivos..." }
    $enUso = @{}
    $firmadoPorDispositivo = @{}
    try {
        foreach ($f in @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop)) {
            if ($f.InfName) { $enUso["$($f.InfName)".ToLower()] = $true }
            if ($f.DeviceID) { $firmadoPorDispositivo["$($f.DeviceID)"] = $f }
        }
    } catch { Write-Log "No se pudo leer la lista de controladores en uso: $($_.Exception.Message)" -Tipo AVISO }

    # 1) Dispositivos conectados con el controlador roto, bloqueado o sin firma valida
    if ($Progreso) { Update-VentanaProgreso -Ventana $Progreso -Porcentaje 25 -Estado "Buscando dispositivos con controladores no compatibles..." }
    $codigosProblema = @{
        10 = "El dispositivo no puede iniciar con este controlador (puede ser incompatible)."
        31 = "Windows no puede cargar el controlador de este dispositivo."
        37 = "Windows no pudo inicializar el controlador (incompatible o danado)."
        39 = "El controlador esta danado, falta o no es compatible con este Windows."
        43 = "Windows detuvo el dispositivo porque el controlador reporto problemas."
        48 = "Windows bloqueo este controlador por problemas conocidos con esta version de Windows."
        52 = "Windows no puede verificar la firma digital del controlador (sin firma valida)."
    }
    try {
        $entidades = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -and $codigosProblema.ContainsKey([int]$_.ConfigManagerErrorCode) })
        foreach ($e in $entidades) {
            $firmado = $firmadoPorDispositivo["$($e.DeviceID)"]
            $inf = $null; $ver = $null; $fecha = "Desconocida"
            if ($firmado) {
                if ("$($firmado.InfName)" -match '^oem\d+\.inf$') { $inf = "$($firmado.InfName)" }
                $ver = $firmado.DriverVersion
                if ($firmado.DriverDate) { try { $fecha = ([datetime]$firmado.DriverDate).ToString('yyyy-MM-dd') } catch { } }
            }
            $lista.Add([PSCustomObject]@{
                Tipo       = 'No compatible'
                Nombre     = if ($e.Name) { "$($e.Name)" } else { "$($e.DeviceID)" }
                Fabricante = "$($e.Manufacturer)"
                Version    = "$ver"
                Fecha      = $fecha
                Motivo     = "Codigo $([int]$e.ConfigManagerErrorCode): " + $codigosProblema[[int]$e.ConfigManagerErrorCode]
                Paquete    = $inf
                InstanceId = "$($e.DeviceID)"
                Origen     = 'dispositivo'
            })
        }
    } catch { Write-Log "No se pudo revisar los dispositivos con error: $($_.Exception.Message)" -Tipo AVISO }

    # 2) Paquetes de terceros del almacen de controladores
    if ($Progreso) { Update-VentanaProgreso -Ventana $Progreso -Porcentaje 40 -Estado "Leyendo el almacen de controladores de Windows (puede tardar un poco)..." }
    $paquetes = @()
    try {
        $paquetes = @(Get-WindowsDriver -Online -ErrorAction Stop | Where-Object { -not $_.Inbox -and -not $_.BootCritical })
    } catch { Write-Log "No se pudo leer el almacen de controladores: $($_.Exception.Message)" -Tipo AVISO }

    if ($Progreso) { Update-VentanaProgreso -Ventana $Progreso -Porcentaje 75 -Estado "Comparando versiones de cada controlador..." }
    $grupos = $paquetes | Group-Object {
        $hoja = ("$($_.OriginalFileName)" -split '[\\/]')[-1].ToLower()
        $prov = "$($_.ProviderName)".ToLower()
        $cls = "$($_.ClassName)".ToLower()
        "$hoja|$prov|$cls"
    }
    foreach ($g in $grupos) {
        $ordenados = @($g.Group | Sort-Object @{ Expression = { $_.Date }; Descending = $true }, @{ Expression = { $_.Version }; Descending = $true })
        for ($i = 0; $i -lt $ordenados.Count; $i++) {
            $pk = $ordenados[$i]
            if ($enUso.ContainsKey("$($pk.Driver)".ToLower())) { continue }
            $hojaInf = ("$($pk.OriginalFileName)" -split '[\\/]')[-1]
            $fechaPk = if ($pk.Date) { ([datetime]$pk.Date).ToString('yyyy-MM-dd') } else { "Desconocida" }
            if ($i -gt 0) {
                $tipo = 'Version anterior'
                $motivo = "Ya hay una version mas nueva ($($ordenados[0].Version)) de este mismo controlador y ningun dispositivo usa esta."
            } else {
                $tipo = 'Sin uso'
                $motivo = "Ningun dispositivo conectado usa este controlador (suele ser de hardware que ya no tienes). Si reconectas ese hardware, tendras que volver a instalarlo."
            }
            $lista.Add([PSCustomObject]@{
                Tipo       = $tipo
                Nombre     = "$hojaInf  [$($pk.Driver)]  - $($pk.ClassName)"
                Fabricante = "$($pk.ProviderName)"
                Version    = "$($pk.Version)"
                Fecha      = $fechaPk
                Motivo     = $motivo
                Paquete    = "$($pk.Driver)"
                InstanceId = $null
                Origen     = 'paquete'
            })
        }
    }

    # 3) Dispositivos que estuvieron conectados y ya no estan (restos de controladores)
    if ($Progreso) { Update-VentanaProgreso -Ventana $Progreso -Porcentaje 90 -Estado "Buscando dispositivos que ya no estan conectados..." }
    $clasesFantasma = @('USB', 'USBDevice', 'HIDClass', 'WPD', 'DiskDrive', 'CDROM', 'Monitor', 'Net', 'Bluetooth', 'MEDIA',
                        'Printer', 'Camera', 'Image', 'Keyboard', 'Mouse', 'SmartCardReader', 'Modem', 'Ports', 'SCSIAdapter')
    try {
        $yaListados = @{}
        foreach ($x in $lista) { if ($x.InstanceId) { $yaListados[$x.InstanceId] = $true } }
        $fantasmas = @(Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -eq 'Unknown' -and ($clasesFantasma -contains $_.Class) })
        foreach ($d in $fantasmas) {
            if ($yaListados.ContainsKey("$($d.InstanceId)")) { continue }
            $nombreFantasma = if ($d.FriendlyName) { "$($d.FriendlyName)" } elseif ($d.Name) { "$($d.Name)" } else { "$($d.InstanceId)" }
            $lista.Add([PSCustomObject]@{
                Tipo       = 'No conectado'
                Nombre     = "$nombreFantasma  - $($d.Class)"
                Fabricante = "$($d.Manufacturer)"
                Version    = ""
                Fecha      = ""
                Motivo     = "Dispositivo que estuvo conectado y ya no esta presente (resto de un controlador anterior). Si lo vuelves a conectar, Windows lo detecta de nuevo."
                Paquete    = $null
                InstanceId = "$($d.InstanceId)"
                Origen     = 'dispositivo'
            })
        }
    } catch { Write-Log "No se pudo revisar los dispositivos no conectados: $($_.Exception.Message)" -Tipo AVISO }

    $orden = @{ 'No compatible' = 0; 'Version anterior' = 1; 'Sin uso' = 2; 'No conectado' = 3 }
    return @($lista | Sort-Object @{ Expression = { $orden[$_.Tipo] } }, Nombre)
}

# Borra los elementos elegidos. Antes de borrar un paquete guarda una copia en
# Documentos\DragonTool_RespaldoControladores\<fecha>. Devuelve lo eliminado y lo que fallo.
function Remove-ControladoresSeleccionados {
    param($Items)
    $eliminados = New-Object System.Collections.Generic.List[object]
    $fallidos = New-Object System.Collections.Generic.List[string]
    $conservados = New-Object System.Collections.Generic.List[string]
    $requiereReinicio = $false
    $carpetaRespaldo = $null
    $total = @($Items).Count

    $prog = New-VentanaProgreso -Titulo "Eliminando controladores seleccionados"
    $contador = 0
    foreach ($it in $Items) {
        $contador++
        $pct = [int](($contador - 1) * 100 / [math]::Max(1, $total))
        Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "($contador de $total) $($it.Nombre)" -LogLinea "Procesando: $($it.Nombre)"
        try {
            # Copia de seguridad del paquete antes de tocarlo
            if ($it.Paquete) {
                if (-not $carpetaRespaldo) {
                    $carpetaRespaldo = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("DragonTool_RespaldoControladores\" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
                    New-Item -ItemType Directory -Path $carpetaRespaldo -Force | Out-Null
                }
                $destinoPk = Join-Path $carpetaRespaldo ("$($it.Paquete)".Replace('.inf', ''))
                New-Item -ItemType Directory -Path $destinoPk -Force | Out-Null
                & pnputil.exe /export-driver "$($it.Paquete)" "$destinoPk" 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  (No se pudo guardar la copia de '$($it.Paquete)'; se continua.)" }
            }

            if ($it.Origen -eq 'paquete') {
                $salida = & pnputil.exe /delete-driver "$($it.Paquete)" 2>&1
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
                    if ($LASTEXITCODE -eq 3010) { $requiereReinicio = $true }
                    $eliminados.Add($it)
                    Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  Eliminado el paquete $($it.Paquete)."
                } else {
                    $fallidos.Add("$($it.Nombre): Windows no permitio borrarlo (probablemente sigue en uso).")
                    Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  No se pudo borrar $($it.Paquete): sigue en uso o esta protegido."
                }
            } else {
                & pnputil.exe /remove-device "$($it.InstanceId)" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
                    if ($LASTEXITCODE -eq 3010) { $requiereReinicio = $true }
                    $eliminados.Add($it)
                    Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  Dispositivo quitado."
                    # Si ademas tenia un paquete de terceros propio, intenta borrarlo sin forzar
                    if ($it.Paquete) {
                        & pnputil.exe /delete-driver "$($it.Paquete)" 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
                            Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  Tambien se borro su paquete $($it.Paquete)."
                        } else {
                            $conservados.Add("$($it.Paquete) (lo siguen usando otros dispositivos)")
                            Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  El paquete $($it.Paquete) se conserva: lo usan otros dispositivos."
                        }
                    }
                } else {
                    $fallidos.Add("$($it.Nombre): no se pudo quitar el dispositivo (codigo $LASTEXITCODE).")
                    Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  No se pudo quitar el dispositivo (codigo $LASTEXITCODE)."
                }
            }
        } catch {
            $fallidos.Add("$($it.Nombre): $($_.Exception.Message)")
            Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  Error: $($_.Exception.Message)"
        }
    }
    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Proceso terminado: $($eliminados.Count) de $total eliminado(s)."
    return [PSCustomObject]@{
        Eliminados  = $eliminados
        Fallidos    = $fallidos
        Conservados = $conservados
        Reinicio    = $requiereReinicio
        Respaldo    = $carpetaRespaldo
    }
}

function Show-VentanaControladoresObsoletos {
    param($Items)
    [xml]$xamlObs = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Controladores obsoletos o no compatibles - The Dragon Tool" Height="640" Width="1020"
        WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)
$($Global:RecursosGridXaml)
  </Window.Resources>
  <DockPanel Margin="14">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Foreground="White" TextWrapping="Wrap" Margin="0,0,0,6"
               Text="Marca los controladores que quieras borrar (Ctrl o Mayus + clic para elegir varios). Antes de borrar cada paquete se guarda una copia de seguridad en Documentos."/>
    <TextBlock x:Name="TxtObsResumen" DockPanel.Dock="Top" Foreground="#66AEFF" FontWeight="Bold" Margin="0,0,0,8" TextWrapping="Wrap"/>
    <WrapPanel DockPanel.Dock="Bottom" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnObsTodo" Content="Seleccionar todo" Width="150" Margin="0,0,8,0"/>
      <Button x:Name="BtnObsAnteriores" Content="Solo versiones anteriores" Width="190" Margin="0,0,8,0"/>
      <Button x:Name="BtnObsNinguno" Content="Quitar seleccion" Width="140" Margin="0,0,8,0"/>
      <Button x:Name="BtnObsEliminar" Content="🗑️ Eliminar seleccionados" Width="210" Margin="0,0,8,0" FontWeight="Bold"/>
      <Button x:Name="BtnObsCerrar" Content="Cerrar" Width="100"/>
    </WrapPanel>
    <DataGrid x:Name="GridObs" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Extended" SelectionUnit="FullRow"
              Background="#151B27" RowBackground="#151B27" AlternatingRowBackground="#1C2635" Foreground="White"
              BorderBrush="#232B3D" HorizontalGridLinesBrush="#232B3D" VerticalGridLinesBrush="#232B3D" RowHeaderWidth="0"
              CanUserAddRows="False" HeadersVisibility="Column">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Tipo" Binding="{Binding Tipo}" Width="120"/>
        <DataGridTextColumn Header="Controlador / dispositivo" Binding="{Binding Nombre}" Width="2.2*"/>
        <DataGridTextColumn Header="Fabricante" Binding="{Binding Fabricante}" Width="1.1*"/>
        <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="110"/>
        <DataGridTextColumn Header="Fecha" Binding="{Binding Fecha}" Width="95"/>
        <DataGridTextColumn Header="Por que aparece" Binding="{Binding Motivo}" Width="3*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
"@
    $readerObs = New-Object System.Xml.XmlNodeReader $xamlObs
    $win = [Windows.Markup.XamlReader]::Load($readerObs)
    Iniciar-EfectosNeon -Ventana $win
    $grid = $win.FindName("GridObs")
    $txtResumen = $win.FindName("TxtObsResumen")
    $coleccion = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($it in $Items) { $coleccion.Add($it) }
    $grid.ItemsSource = $coleccion

    $actualizarResumen = {
        $nc = @($coleccion | Where-Object { $_.Tipo -eq 'No compatible' }).Count
        $na = @($coleccion | Where-Object { $_.Tipo -eq 'Version anterior' }).Count
        $ns = @($coleccion | Where-Object { $_.Tipo -eq 'Sin uso' }).Count
        $nn = @($coleccion | Where-Object { $_.Tipo -eq 'No conectado' }).Count
        $txtResumen.Text = "Encontrados: $($coleccion.Count)   |   No compatibles: $nc   |   Versiones anteriores: $na   |   Sin uso: $ns   |   No conectados: $nn"
    }
    & $actualizarResumen

    $win.FindName("BtnObsTodo").Add_Click({ $grid.SelectAll() })
    $win.FindName("BtnObsNinguno").Add_Click({ $grid.UnselectAll() })
    $win.FindName("BtnObsAnteriores").Add_Click({
        $grid.UnselectAll()
        foreach ($elemento in $coleccion) {
            if ($elemento.Tipo -eq 'Version anterior') { [void]$grid.SelectedItems.Add($elemento) }
        }
    })
    $win.FindName("BtnObsCerrar").Add_Click({ $win.Close() })
    $win.FindName("BtnObsEliminar").Add_Click({
        $seleccion = @($grid.SelectedItems)
        if ($seleccion.Count -eq 0) {
            Show-Aviso "Selecciona primero uno o mas elementos de la lista (Ctrl o Mayus + clic para elegir varios)." "Sin seleccion"
            return
        }
        $hayRiesgo = @($seleccion | Where-Object { $_.Tipo -eq 'Sin uso' -or $_.Tipo -eq 'No compatible' }).Count -gt 0
        $mensaje = "Se van a eliminar $($seleccion.Count) elemento(s).`n`nAntes de borrar cada paquete se guarda una copia en Documentos\DragonTool_RespaldoControladores."
        if ($hayRiesgo) {
            $mensaje += "`n`nAtencion: entre lo seleccionado hay controladores 'Sin uso' o 'No compatibles'. Si borras uno de hardware que todavia necesitas, ese hardware dejara de funcionar hasta que lo reinstales."
        }
        $mensaje += "`n`n¿Continuar?"
        if (-not (Show-Confirm $mensaje "Eliminar controladores")) { return }
        $resultado = Remove-ControladoresSeleccionados -Items $seleccion
        foreach ($borrado in $resultado.Eliminados) { [void]$coleccion.Remove($borrado) }
        & $actualizarResumen
        Write-Log "Controladores obsoletos eliminados: $($resultado.Eliminados.Count) de $($seleccion.Count)." -Tipo OK
        $texto = "Eliminados: $($resultado.Eliminados.Count) de $($seleccion.Count)."
        if ($resultado.Respaldo) { $texto += "`n`nCopia de seguridad en:`n$($resultado.Respaldo)" }
        if ($resultado.Conservados.Count -gt 0) { $texto += "`n`nSe conservaron (los usan otros dispositivos):`n - " + ($resultado.Conservados -join "`n - ") }
        if ($resultado.Fallidos.Count -gt 0) { $texto += "`n`nNo se pudieron borrar:`n - " + ($resultado.Fallidos -join "`n - ") }
        if ($resultado.Reinicio) { $texto += "`n`nWindows pide reiniciar el equipo para terminar de aplicar los cambios." }
        Show-Aviso $texto "Resultado"
    })
    $win.ShowDialog() | Out-Null
}

function Accion-BuscarControladoresObsoletos {
    if (-not (Requiere-Admin)) { return }
    Write-Log "Buscando controladores obsoletos o no compatibles..."
    $prog = New-VentanaProgreso -Titulo "Buscando controladores obsoletos o no compatibles"
    $encontrados = @()
    try {
        $encontrados = @(Get-ControladoresObsoletos -Progreso $prog)
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Busqueda terminada: $($encontrados.Count) elemento(s)."
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error durante la busqueda."
        Write-Log "No se pudo completar la busqueda de controladores obsoletos: $($_.Exception.Message)" -Tipo ERROR
        return
    }
    if ($encontrados.Count -eq 0) {
        Write-Log "No se encontraron controladores obsoletos ni incompatibles." -Tipo OK
        Show-Aviso "No se encontro ningun controlador obsoleto ni incompatible. Todo parece en orden." "Todo en orden"
        return
    }
    Write-Log "Controladores obsoletos o no compatibles encontrados: $($encontrados.Count)" -Tipo AVISO
    Show-VentanaControladoresObsoletos -Items $encontrados
    $Script:_driversExpFecha = $null   # la lista en cache ya no es vigente
}

# Cache de la lista de controladores: abrir la ventana por segunda vez es instantaneo.
$Script:_todosLosDriversExp = @()
$Script:_driversExpFecha = $null

# Ventana con la lista de controladores. Se abre al instante mostrando "Cargando..." y
# despues llena la lista (asi no hay que esperar a que termine la consulta para ver la ventana).
#   Modo 'Todos'     : todos los controladores instalados
#   Modo 'Atencion'  : solo los antiguos o con problemas
#   Modo 'Faltantes' : dispositivos sin controlador instalado
function Show-VentanaListaControladores {
    param([ValidateSet('Todos', 'Atencion', 'Faltantes')][string]$Modo = 'Todos')
    $tituloVentana = switch ($Modo) {
        'Atencion'  { "Controladores que necesitan atencion" }
        'Faltantes' { "Dispositivos sin controlador instalado" }
        default     { "Controladores instalados" }
    }
    $ayudaVentana = switch ($Modo) {
        'Atencion'  { "Controladores con mas de 2 años de antigüedad o con algun problema. Selecciona uno para buscar su descarga, instalarlo o eliminarlo." }
        'Faltantes' { "Hardware detectado que no tiene controlador instalado o tiene problemas. Selecciona uno para descargarlo e instalarlo automaticamente o instalarlo desde un archivo .inf." }
        default     { "Todos los controladores instalados, con version, fecha y estado. Escribe para filtrar por nombre, fabricante o clase." }
    }
    $visEliminar = if ($Modo -eq 'Faltantes') { "Collapsed" } else { "Visible" }

    [xml]$xamlLista = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$tituloVentana - The Dragon Tool" Height="660" Width="1120" WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)
$($Global:RecursosGridXaml)
  </Window.Resources>
  <DockPanel Margin="14">
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <Button x:Name="BtnVolverVentana" DockPanel.Dock="Left" Content="⬅  Volver" Width="110" Height="34" Margin="0,0,14,0"/>
      <TextBlock Text="$tituloVentana" Foreground="White" FontSize="17" FontWeight="Bold" VerticalAlignment="Center"/>
    </DockPanel>
    <TextBlock DockPanel.Dock="Top" Text="$ayudaVentana" Foreground="#7C93BD" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8" MaxWidth="520" HorizontalAlignment="Left">
      <TextBlock Text="🔍" VerticalAlignment="Center" Margin="0,0,8,0" FontSize="14"/>
      <TextBox x:Name="TxtListaBuscar" Padding="8,6" Background="#151B27" Foreground="#EAF0FA" BorderBrush="#232B3D" CaretBrush="#5B9CFF"/>
    </DockPanel>
    <TextBlock x:Name="TxtListaResumen" DockPanel.Dock="Top" Foreground="#66AEFF" FontWeight="Bold" Margin="0,0,0,6" TextWrapping="Wrap" Text="Preparando la lista..."/>
    <ProgressBar x:Name="BarraCargaLista" DockPanel.Dock="Top" Value="100" Height="18" Margin="0,0,0,8"/>
    <WrapPanel DockPanel.Dock="Bottom" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnListaDescargar" Content="⬇️ Descargar e instalar" Width="200" Margin="0,0,8,0"/>
      <Button x:Name="BtnListaInf" Content="📂 Instalar desde archivo (.inf)" Width="230" Margin="0,0,8,0"/>
      <Button x:Name="BtnListaWeb" Content="🌐 Abrir pagina de descarga" Width="215" Margin="0,0,8,0"/>
      <Button x:Name="BtnListaEliminar" Content="🗑️ Eliminar seleccionado" Width="195" Margin="0,0,8,0" Visibility="$visEliminar"/>
      <Button x:Name="BtnListaActualizar" Content="🔄 Actualizar lista" Width="150"/>
    </WrapPanel>
    <DataGrid x:Name="GridLista" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single" SelectionUnit="FullRow"
              Background="#151B27" RowBackground="#151B27" AlternatingRowBackground="#1C2635" Foreground="White"
              BorderBrush="#232B3D" HorizontalGridLinesBrush="#232B3D" VerticalGridLinesBrush="#232B3D" RowHeaderWidth="0"
              CanUserAddRows="False" HeadersVisibility="Column">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Dispositivo" Binding="{Binding Nombre}" Width="2*"/>
        <DataGridTextColumn Header="Fabricante" Binding="{Binding Fabricante}" Width="1.2*"/>
        <DataGridTextColumn Header="Clase" Binding="{Binding Clase}" Width="0.8*"/>
        <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="*"/>
        <DataGridTextColumn Header="Fecha" Binding="{Binding Fecha}" Width="0.8*"/>
        <DataGridTextColumn Header="Estado" Binding="{Binding Estado}" Width="0.8*"/>
        <DataGridTextColumn Header="Recomendacion" Binding="{Binding Recomendacion}" Width="2.2*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
"@
    $readerLista = New-Object System.Xml.XmlNodeReader $xamlLista
    $win = [Windows.Markup.XamlReader]::Load($readerLista)
    Iniciar-EfectosNeon -Ventana $win
    $grid = $win.FindName("GridLista")
    $txtBuscar = $win.FindName("TxtListaBuscar")
    $txtResumen = $win.FindName("TxtListaResumen")
    $barraCarga = $win.FindName("BarraCargaLista")
    $est = @{ Datos = @(); Total = 0; Cargado = $false }

    $aplicarFiltro = {
        $vista = @($est.Datos)
        $textoBuscado = $txtBuscar.Text
        if (-not [string]::IsNullOrWhiteSpace($textoBuscado)) {
            $patron = [regex]::Escape($textoBuscado)
            $vista = @($est.Datos | Where-Object {
                $_.Nombre -match $patron -or $_.Fabricante -match $patron -or $_.Clase -match $patron -or $_.Recomendacion -match $patron
            })
        }
        $grid.ItemsSource = $vista
        $txtResumen.Text = switch ($Modo) {
            'Faltantes' {
                if (@($est.Datos).Count -eq 0) { "No se detecto ningun dispositivo sin controlador. Todo tu hardware tiene un driver instalado." }
                else { "Dispositivos sin controlador o con problemas: $(@($est.Datos).Count)   |   Mostrando: $($vista.Count)" }
            }
            'Atencion' {
                if (@($est.Datos).Count -eq 0) { "Todos los controladores estan al dia. No se detectaron problemas." }
                else { "Necesitan atencion: $(@($est.Datos).Count) de $($est.Total) controladores   |   Mostrando: $($vista.Count)" }
            }
            default { "Total: $(@($est.Datos).Count) controlador(es)   |   Mostrando: $($vista.Count)" }
        }
    }

    $cargar = {
        param([bool]$Forzar = $false)
        $barraCarga.Visibility = [System.Windows.Visibility]::Visible
        $txtResumen.Text = "Cargando la lista de controladores... un momento."
        Wait-UI -Milisegundos 1
        if ($Modo -eq 'Faltantes') {
            $est.Datos = @(Get-ControladoresFaltantes)
            $est.Total = @($est.Datos).Count
        } else {
            $vigente = ($Script:_todosLosDriversExp.Count -gt 0) -and $Script:_driversExpFecha -and (((Get-Date) - $Script:_driversExpFecha).TotalMinutes -lt 10)
            if ($Forzar -or -not $vigente) {
                Write-Log "Cargando lista de controladores instalados..."
                $Script:_todosLosDriversExp = @(Get-TodosLosControladores)
                $Script:_driversExpFecha = Get-Date
                Write-Log "Controladores listados: $($Script:_todosLosDriversExp.Count)" -Tipo OK
            }
            $est.Total = $Script:_todosLosDriversExp.Count
            $est.Datos = if ($Modo -eq 'Atencion') { @($Script:_todosLosDriversExp | Where-Object { $_.Recomendacion -ne 'Al dia' }) } else { @($Script:_todosLosDriversExp) }
        }
        $barraCarga.Visibility = [System.Windows.Visibility]::Collapsed
        & $aplicarFiltro
    }

    # La ventana se muestra primero y la lista se carga justo despues del primer dibujado
    $win.Add_ContentRendered({
        if ($est.Cargado) { return }
        $est.Cargado = $true
        & $cargar $false
    })
    $txtBuscar.Add_TextChanged({ & $aplicarFiltro })
    $win.FindName("BtnListaActualizar").Add_Click({ & $cargar $true })
    $win.FindName("BtnListaDescargar").Add_Click({
        $sel = $grid.SelectedItem
        if (-not $sel) { Show-Aviso "Selecciona primero un dispositivo de la lista." "Sin seleccion"; return }
        Accion-DescargarInstalarControladorFaltante -Item $sel
        $Script:_driversExpFecha = $null
        & $cargar $true
    })
    $win.FindName("BtnListaInf").Add_Click({
        $sel = $grid.SelectedItem
        if (-not $sel) { Show-Aviso "Selecciona primero un dispositivo de la lista." "Sin seleccion"; return }
        Accion-InstalarControladorDesdeArchivo -Item $sel
        $Script:_driversExpFecha = $null
        & $cargar $true
    })
    $win.FindName("BtnListaWeb").Add_Click({
        $sel = $grid.SelectedItem
        if (-not $sel) { Show-Aviso "Selecciona un controlador de la lista." "Sin seleccion"; return }
        Abrir-PaginaParaControlador -Item $sel
    })
    $win.FindName("BtnListaEliminar").Add_Click({
        $sel = $grid.SelectedItem
        if (-not $sel) { Show-Aviso "Selecciona un controlador de la lista." "Sin seleccion"; return }
        if (Accion-EliminarControlador -Item $sel) {
            $Script:_driversExpFecha = $null
            & $cargar $true
        }
    })
    $win.ShowDialog() | Out-Null
}

function Abrir-PaginaParaControlador {
    param($Item)
    $clase = "$($Item.Clase)"
    $fab = "$($Item.Fabricante)"
    $nombre = "$($Item.Nombre)"
    $hwid = "$($Item.HardwareID)"
    $textoBusqueda = if ($hwid) { $hwid } else { $nombre }

    if ($clase -match 'Display' -or $nombre -match 'NVIDIA|GeForce|Radeon|Graphics') {
        $vendor =
            if ($nombre -match 'NVIDIA|GeForce' -or $fab -match 'NVIDIA') { 'NVIDIA' }
            elseif ($nombre -match 'AMD|Radeon' -or $fab -match 'Advanced Micro') { 'AMD' }
            elseif ($nombre -match 'Intel' -or $fab -match 'Intel') { 'Intel' }
            else { $null }
        if ($vendor) {
            Buscar-DriverGPU -Fabricante $vendor -ModeloDetectado $textoBusqueda
            return
        }
    }

    $coincidePlaca = $Script:UrlPlaca.Keys | Where-Object { $fab -match [regex]::Escape($_) } | Select-Object -First 1
    if ($coincidePlaca) {
        Show-VentanaNavegador -Url $Script:UrlPlaca[$coincidePlaca] -Titulo "Controladores $coincidePlaca" -TextoRespaldo $textoBusqueda
        return
    }
    $coincideLaptop = $Script:UrlLaptop.Keys | Where-Object { $fab -match [regex]::Escape($_) } | Select-Object -First 1
    if ($coincideLaptop) {
        Show-VentanaNavegador -Url $Script:UrlLaptop[$coincideLaptop] -Titulo "Controladores $coincideLaptop" -TextoRespaldo $textoBusqueda
        return
    }

    # No se pudo determinar el fabricante: se busca directo en Google usando
    # el ID de hardware exacto del controlador (o el nombre si no hay ID).
    Write-Log "No se identifico un fabricante conocido para '$nombre'. Buscando en Google con su ID de hardware..." -Tipo AVISO
    $urlGoogle = Get-UrlRespaldoBusqueda -Texto $textoBusqueda
    Show-VentanaNavegador -Url $urlGoogle -Titulo "Busqueda: $nombre"
}

function Accion-AbrirAdministradorDispositivos {
    Start-Process devmgmt.msc
    Write-Log "Administrador de dispositivos abierto. Clic derecho > Actualizar controlador." -Tipo OK
}

function Accion-AbrirActualizacionesOpcionales {
    try {
        Start-Process "ms-settings:windowsupdate-optionalupdates"
        Write-Log "Seccion de actualizaciones opcionales abierta (incluye controladores)." -Tipo OK
    } catch {
        Write-Log "No se pudo abrir la seccion de actualizaciones opcionales." -Tipo AVISO
    }
}

function Accion-ActualizarControladoresAuto {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Se instalara el modulo PSWindowsUpdate (si no esta) y se buscaran drivers nuevos. Puede tardar varios minutos. ¿Continuar?")) { return }
    try {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Log "Instalando modulo PSWindowsUpdate..."
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-Log "Buscando e instalando actualizaciones de controladores..."
        Get-WindowsUpdate -Category "Drivers" -Install -AcceptAll -AutoReboot:$false -ErrorAction Stop
        Write-Log "Actualizacion de controladores finalizada. Reinicia si algun driver lo pide." -Tipo OK
    } catch {
        Write-Log "No se pudo completar la actualizacion automatica: $($_.Exception.Message)" -Tipo ERROR
        Write-Log "Prueba con 'Administrador de dispositivos' o 'Actualizaciones opcionales' como alternativa." -Tipo AVISO
    }
}

function Accion-PausarActualizaciones7Dias {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "¿Pausar las actualizaciones de Windows por 7 dias?")) { return }
    try {
        $fecha = (Get-Date).AddDays(7).ToString("yyyy-MM-ddTHH:mm:ssK")
        $path = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "PauseUpdatesExpiryTime" -Value $fecha -Type String
        Write-Log "Actualizaciones pausadas hasta: $fecha" -Tipo OK
    } catch {
        Write-Log "No se pudo pausar las actualizaciones: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-DeshabilitarWindowsUpdate {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "AVISO: dejar de recibir actualizaciones puede exponerte a fallos de seguridad. ¿Deshabilitar el servicio de Windows Update de todas formas?")) { return }
    try {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Set-Service -Name wuauserv -StartupType Disabled
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "NoAutoUpdate" -Value 1 -Type DWord
        Write-Log "Servicio de Windows Update detenido y deshabilitado. Usa 'Reanudar actualizaciones' para revertir." -Tipo OK
    } catch {
        Write-Log "No se pudo deshabilitar Windows Update: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-ReanudarActualizaciones {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto reactivara las actualizaciones automaticas de Windows. ¿Continuar?")) { return }
    try {
        $pathAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (Test-Path $pathAU) { Set-ItemProperty -Path $pathAU -Name "NoAutoUpdate" -Value 0 -Type DWord -ErrorAction SilentlyContinue }
        $pathUX = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (Test-Path $pathUX) { Remove-ItemProperty -Path $pathUX -Name "PauseUpdatesExpiryTime" -ErrorAction SilentlyContinue }
        Set-Service -Name wuauserv -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Write-Log "Actualizaciones de Windows reactivadas." -Tipo OK
    } catch {
        Write-Log "No se pudo reactivar las actualizaciones: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-ForzarBusquedaUpdates {
    if (-not (Requiere-Admin)) { return }
    try {
        Start-Process "UsoClient.exe" -ArgumentList "StartScan" -ErrorAction Stop
        Write-Log "Busqueda de actualizaciones de Windows iniciada." -Tipo OK
    } catch {
        Start-Process "ms-settings:windowsupdate"
        Write-Log "Se abrio la pantalla de Windows Update; pulsa 'Buscar actualizaciones'." -Tipo INFO
    }
}

function Accion-HistorialUpdates {
    Start-Process "ms-settings:windowsupdate-history"
    Write-Log "Historial de actualizaciones abierto." -Tipo OK
}

function Accion-RepararWindowsUpdate {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto reinicia por completo el componente de Windows Update (detiene servicios y renueva su cache). Util cuando las actualizaciones se quedan trabadas. ¿Continuar?")) { return }
    try {
        Write-Log "Deteniendo servicios de Windows Update..."
        foreach ($s in @('wuauserv','bits','cryptsvc','msiserver')) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        }
        $fecha = Get-Date -Format "yyyyMMddHHmmss"
        Rename-Item -Path "$env:WINDIR\SoftwareDistribution" -NewName "SoftwareDistribution.old.$fecha" -ErrorAction SilentlyContinue
        Rename-Item -Path "$env:WINDIR\System32\catroot2" -NewName "catroot2.old.$fecha" -ErrorAction SilentlyContinue
        foreach ($s in @('wuauserv','bits','cryptsvc','msiserver')) {
            Start-Service -Name $s -ErrorAction SilentlyContinue
        }
        Write-Log "Windows Update reparado y reiniciado correctamente." -Tipo OK
    } catch {
        Write-Log "No se pudo completar la reparacion de Windows Update: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-ActualizarDefenderFirmas {
    try {
        Update-MpSignature -ErrorAction Stop
        Write-Log "Firmas de Windows Defender actualizadas." -Tipo OK
    } catch {
        Write-Log "No se pudieron actualizar las firmas de Windows Defender." -Tipo AVISO
    }
}

# ---------------------------------------------------------------------------
#  RED Y SEGURIDAD
# ---------------------------------------------------------------------------

function Accion-VaciarDNS {
    Write-Log "Vaciando cache DNS..."
    try {
        ipconfig /flushdns | Out-Null
        Write-Log "Cache DNS vaciada." -Tipo OK
    } catch {
        Write-Log "Problema al vaciar la cache DNS." -Tipo AVISO
    }
}

function Accion-RenovarIP {
    if (-not (Show-Confirm "Esto libera y renueva tu direccion IP. Puede cortar la conexion unos segundos. ¿Continuar?")) { return }
    try {
        ipconfig /release | Out-Null
        ipconfig /renew | Out-Null
        Write-Log "Direccion IP renovada." -Tipo OK
    } catch {
        Write-Log "No se pudo renovar la IP." -Tipo AVISO
    }
}

function Accion-AnalisisDefender {
    if (-not (Show-Confirm "Se ejecutara un analisis rapido con Windows Defender. Puede tardar unos minutos. ¿Continuar?")) { return }
    Write-Log "Ejecutando analisis rapido con Windows Defender..."
    try {
        Start-MpScan -ScanType QuickScan
        Write-Log "Analisis rapido completado." -Tipo OK
    } catch {
        Write-Log "No se pudo ejecutar el analisis (verifica que Windows Defender este activo)." -Tipo AVISO
    }
}

function Accion-VerAdaptadoresRed {
    Write-Log "Adaptadores de red:"
    try {
        $adaptadores = Get-NetAdapter -ErrorAction Stop
        foreach ($a in $adaptadores) {
            Write-Log " - $($a.Name) | Estado: $($a.Status) | Velocidad: $($a.LinkSpeed)"
        }
    } catch {
        Write-Log "No se pudo obtener la lista de adaptadores de red." -Tipo AVISO
    }
}

function Accion-ReiniciarAdaptadoresRed {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto reinicia todos los adaptadores de red activos (se cortara la conexion unos segundos). ¿Continuar?")) { return }
    try {
        Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Restart-NetAdapter -Confirm:$false -ErrorAction Stop
        Write-Log "Adaptadores de red reiniciados." -Tipo OK
    } catch {
        Write-Log "No se pudieron reiniciar los adaptadores de red." -Tipo ERROR
    }
}

function Accion-ResetWinsockTCPIP {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto restablece Winsock y la pila TCP/IP (soluciona muchos problemas de conexion). Requiere reiniciar el equipo despues. ¿Continuar?")) { return }
    try {
        netsh winsock reset | Out-Null
        netsh int ip reset | Out-Null
        Write-Log "Winsock y TCP/IP restablecidos. Reinicia el equipo para completar el proceso." -Tipo OK
    } catch {
        Write-Log "No se pudo restablecer Winsock/TCP/IP." -Tipo ERROR
    }
}

function Accion-VerIP {
    Write-Log "Consultando direcciones IP..."
    try {
        $locales = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' }
        foreach ($ip in $locales) { Write-Log " - IP local ($($ip.InterfaceAlias)): $($ip.IPAddress)" }
    } catch {}
    try {
        $publica = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 8 -ErrorAction Stop
        Write-Log "IP publica: $publica" -Tipo OK
    } catch {
        Write-Log "No se pudo consultar la IP publica (revisa tu conexion a internet)." -Tipo AVISO
    }
}

function Accion-AnalisisDefenderCompleto {
    if (-not (Show-Confirm "Se ejecutara un analisis COMPLETO con Windows Defender. Puede tardar bastante tiempo (horas en discos grandes). ¿Continuar?")) { return }
    Write-Log "Ejecutando analisis completo con Windows Defender (esto puede tardar mucho)..."
    try {
        Start-MpScan -ScanType FullScan
        Write-Log "Analisis completo finalizado." -Tipo OK
    } catch {
        Write-Log "No se pudo ejecutar el analisis completo." -Tipo AVISO
    }
}

function Accion-EstadoFirewall {
    Write-Log "Estado del Firewall de Windows:"
    try {
        $perfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($p in $perfiles) {
            $estado = if ($p.Enabled) { "Activado" } else { "Desactivado" }
            Write-Log " - Perfil $($p.Name): $estado"
        }
    } catch {
        Write-Log "No se pudo consultar el estado del Firewall." -Tipo AVISO
    }
}

# ---------------------------------------------------------------------------
#  SISTEMA
# ---------------------------------------------------------------------------

function Accion-ReiniciarExplorer {
    if (-not (Show-Confirm "Esto cerrara y volvera a abrir el escritorio y la barra de tareas. ¿Continuar?")) { return }
    try {
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
        Start-Process explorer.exe
        Write-Log "Explorer.exe reiniciado." -Tipo OK
    } catch {
        Write-Log "No se pudo reiniciar Explorer." -Tipo AVISO
    }
}

function Accion-ResumenSistema {
    Write-Log "Generando resumen del sistema..."
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRAM = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
    $freeRAM  = [math]::Round($os.FreePhysicalMemory/1MB,1)
    $usoRAM   = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100,1)
    Write-Log "RAM total: $totalRAM GB | RAM libre: $freeRAM GB | Uso de RAM: $usoRAM %" -Tipo OK
    Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
        $libreGB = [math]::Round($_.SizeRemaining/1GB,1)
        $totalGB = [math]::Round($_.Size/1GB,1)
        Write-Log "Disco $($_.DriveLetter): $libreGB GB libres de $totalGB GB"
    }
}

function Accion-CrearPuntoRestauracion {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto crea un punto de restauracion del sistema con la fecha de hoy. ¿Continuar?")) { return }
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "The Dragon Tool - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Punto de restauracion creado correctamente." -Tipo OK
    } catch {
        Write-Log "No se pudo crear el punto de restauracion: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-AbrirRestaurarSistema {
    Start-Process "rstrui.exe"
    Write-Log "Herramienta de Restaurar sistema abierta." -Tipo OK
}

function Accion-VerificarArchivosSistema {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto ejecuta SFC (System File Checker) para revisar y reparar archivos de sistema danados. Puede tardar varios minutos. ¿Continuar?")) { return }
    try {
        Write-Log "Ejecutando SFC /scannow... esto puede tardar." -Tipo INFO
        Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow
        Write-Log "Verificacion de archivos de sistema completada." -Tipo OK
    } catch {
        Write-Log "No se pudo ejecutar SFC." -Tipo ERROR
    }
}

function Accion-RepararImagenWindows {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto ejecuta DISM /RestoreHealth para reparar la imagen de Windows (requiere internet). Puede tardar varios minutos. ¿Continuar?")) { return }
    try {
        Write-Log "Ejecutando DISM /RestoreHealth... esto puede tardar." -Tipo INFO
        Start-Process -FilePath "Dism.exe" -ArgumentList "/online","/Cleanup-Image","/RestoreHealth" -Wait -NoNewWindow
        Write-Log "Reparacion de la imagen de Windows completada." -Tipo OK
    } catch {
        Write-Log "No se pudo reparar la imagen de Windows." -Tipo ERROR
    }
}

function Accion-VariablesEntorno {
    Start-Process "rundll32.exe" -ArgumentList "sysdm.cpl,EditEnvironmentVariables"
    Write-Log "Panel de variables de entorno abierto." -Tipo OK
}

function Accion-InformeEnergia {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto genera un informe de energia de Windows (powercfg /energy), tarda unos 60 segundos. ¿Continuar?")) { return }
    try {
        $destino = Join-Path $Script:ScriptDir "InformeEnergia.html"
        Write-Log "Generando informe de energia (60 segundos aprox.)..." -Tipo INFO
        Start-Process -FilePath "powercfg.exe" -ArgumentList "/energy","/output","`"$destino`"","/duration","60" -Wait -NoNewWindow
        if (Test-Path $destino) {
            Write-Log "Informe de energia generado: $destino" -Tipo OK
            if (Show-Confirm "¿Abrir el informe ahora?") { Start-Process $destino }
        } else {
            Write-Log "No se genero el archivo del informe." -Tipo AVISO
        }
    } catch {
        Write-Log "No se pudo generar el informe de energia." -Tipo ERROR
    }
}

function Accion-ReiniciarEquipo {
    if (-not (Show-Confirm "¿Seguro que quieres REINICIAR el equipo ahora? Se cerraran todos los programas abiertos.")) { return }
    Write-Log "Reiniciando el equipo..." -Tipo OK
    Start-Process "shutdown.exe" -ArgumentList "/r","/t","5"
}

function Accion-ApagarEquipo {
    if (-not (Show-Confirm "¿Seguro que quieres APAGAR el equipo ahora? Se cerraran todos los programas abiertos.")) { return }
    Write-Log "Apagando el equipo..." -Tipo OK
    Start-Process "shutdown.exe" -ArgumentList "/s","/t","5"
}

# ---------------------------------------------------------------------------
#  WINDOWS 11: PERFIL DE BAJA LATENCIA Y EXTRAS
# ---------------------------------------------------------------------------
# AVISO: Windows no tiene un unico interruptor oficial llamado "Perfil de baja
# latencia". Lo que se aplica aqui es un conjunto de ajustes reales y muy
# usados en guias de optimizacion (prioridad de tareas multimedia/juegos,
# sin limite de red para multimedia, GPU acelerada por hardware y energia al
# maximo) que en conjunto reducen la latencia percibida del sistema.

function Aplicar-BajaLatenciaCore {
    try {
        $pathProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty -Path $pathProfile -Name "SystemResponsiveness" -Value 0 -Type DWord
        Set-ItemProperty -Path $pathProfile -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
        Write-Log "Prioridad de tareas en tiempo real ajustada (SystemResponsiveness = 0)." -Tipo OK

        $pathGames = "$pathProfile\Tasks\Games"
        if (-not (Test-Path $pathGames)) { New-Item -Path $pathGames -Force | Out-Null }
        Set-ItemProperty -Path $pathGames -Name "GPU Priority" -Value 8 -Type DWord
        Set-ItemProperty -Path $pathGames -Name "Priority" -Value 6 -Type DWord
        Set-ItemProperty -Path $pathGames -Name "Scheduling Category" -Value "High" -Type String
        Set-ItemProperty -Path $pathGames -Name "SFIO Priority" -Value "High" -Type String
        Write-Log "Prioridad de la categoria 'Games' elevada en el planificador de Windows." -Tipo OK

        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        powercfg -setactive SCHEME_MIN
        Write-Log "Perfil de baja latencia activado." -Tipo OK
    } catch {
        Write-Log "No se pudo aplicar el perfil de baja latencia: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-BajaLatenciaOn {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto aplica un perfil de baja latencia: prioriza tareas multimedia/juegos en el planificador de Windows, quita el limite de red para multimedia, activa la GPU acelerada por hardware y pone el plan de energia en Alto rendimiento. ¿Continuar?")) { return }
    Aplicar-BajaLatenciaCore
    Show-Aviso "Perfil de baja latencia activado.`nReinicia el equipo para que todos los cambios (especialmente el de GPU) surtan efecto completo." "Perfil aplicado"
}

function Accion-BajaLatenciaOff {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto revierte el perfil de baja latencia a los valores tipicos de Windows. ¿Continuar?")) { return }
    try {
        $pathProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty -Path $pathProfile -Name "SystemResponsiveness" -Value 20 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $pathProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -ErrorAction SilentlyContinue

        $pathGames = "$pathProfile\Tasks\Games"
        if (Test-Path $pathGames) {
            Set-ItemProperty -Path $pathGames -Name "Priority" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $pathGames -Name "Scheduling Category" -Value "Medium" -Type String -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $pathGames -Name "SFIO Priority" -Value "Normal" -Type String -ErrorAction SilentlyContinue
        }
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        powercfg -setactive SCHEME_BALANCED
        Write-Log "Perfil de baja latencia revertido a valores tipicos." -Tipo OK
    } catch {
        Write-Log "No se pudo revertir el perfil de baja latencia: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Restart-ExplorerSilencioso {
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Start-Process explorer.exe
    } catch {}
}

function Accion-MenuContextualClasico {
    if (-not (Show-Confirm "Esto restaura el menu contextual clasico (estilo Windows 10) al hacer clic derecho, en vez del menu simplificado de Windows 11. Se reiniciara el Explorador. ¿Continuar?")) { return }
    try {
        $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "(Default)" -Value "" -Type String
        Restart-ExplorerSilencioso
        Write-Log "Menu contextual clasico activado." -Tipo OK
    } catch {
        Write-Log "No se pudo activar el menu contextual clasico." -Tipo AVISO
    }
}

function Accion-MenuContextualModerno {
    if (-not (Show-Confirm "Esto vuelve a activar el menu contextual moderno de Windows 11. Se reiniciara el Explorador. ¿Continuar?")) { return }
    try {
        Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
        Restart-ExplorerSilencioso
        Write-Log "Menu contextual moderno de Windows 11 restaurado." -Tipo OK
    } catch {
        Write-Log "No se pudo restaurar el menu contextual moderno." -Tipo AVISO
    }
}

function Accion-TaskbarIzquierda {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Barra de tareas alineada a la izquierda." -Tipo OK
    } catch {
        Write-Log "No se pudo cambiar la alineacion de la barra de tareas." -Tipo AVISO
    }
}

function Accion-TaskbarCentrada {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Barra de tareas centrada (por defecto en Windows 11)." -Tipo OK
    } catch {
        Write-Log "No se pudo cambiar la alineacion de la barra de tareas." -Tipo AVISO
    }
}

function Accion-SegundosRelojOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSecondsInSystemClock" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Segundos activados en el reloj de la barra de tareas." -Tipo OK
    } catch {
        Write-Log "No se pudo activar los segundos en el reloj." -Tipo AVISO
    }
}

function Accion-SegundosRelojOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSecondsInSystemClock" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Segundos desactivados en el reloj de la barra de tareas." -Tipo OK
    } catch {
        Write-Log "No se pudo desactivar los segundos en el reloj." -Tipo AVISO
    }
}

function Accion-WidgetsOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Boton de Widgets ocultado de la barra de tareas." -Tipo OK
    } catch {
        Write-Log "No se pudo ocultar Widgets." -Tipo AVISO
    }
}

function Accion-WidgetsOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Boton de Widgets mostrado en la barra de tareas." -Tipo OK
    } catch {
        Write-Log "No se pudo mostrar Widgets." -Tipo AVISO
    }
}

function Accion-FinalizarTareaTaskbar {
    if (-not (Show-Confirm "Esto activa la opcion 'Finalizar tarea' al hacer clic derecho sobre una app en la barra de tareas (funcion de Windows 11 23H2 en adelante). ¿Continuar?")) { return }
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskbarDeveloperSettings"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "TaskbarEndTask" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "'Finalizar tarea' activado en el clic derecho de la barra de tareas." -Tipo OK
    } catch {
        Write-Log "No se pudo activar 'Finalizar tarea' (puede no estar disponible en tu version de Windows 11)." -Tipo AVISO
    }
}

function Accion-SnapLayoutsOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0 -Type DWord
        Write-Log "Snap Layouts (menu al pasar el mouse por maximizar) desactivado." -Tipo OK
    } catch {
        Write-Log "No se pudo desactivar Snap Layouts." -Tipo AVISO
    }
}

function Accion-SnapLayoutsOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 1 -Type DWord
        Write-Log "Snap Layouts activado (por defecto en Windows 11)." -Tipo OK
    } catch {
        Write-Log "No se pudo activar Snap Layouts." -Tipo AVISO
    }
}

function Accion-AbrirConfigGraficos {
    Start-Process "ms-settings:display-advancedgraphics"
    Write-Log "Configuracion de graficos (Auto HDR / GPU por aplicacion) abierta." -Tipo OK
}

function Accion-VerEstadoActivacion {
    Write-Log "=== ESTADO DE ACTIVACION DE WINDOWS ===" -Tipo INFO
    try {
        $producto = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop
        if (-not $producto) {
            Write-Log "No se pudo determinar el estado de activacion." -Tipo AVISO
            return
        }
        $estadoTexto = switch ($producto.LicenseStatus) {
            0 { "Sin licencia" }
            1 { "Activado" }
            2 { "Periodo de gracia inicial" }
            3 { "Periodo de gracia extendido" }
            4 { "Modo no genuino (posible manipulacion de la licencia)" }
            5 { "Periodo de gracia de notificacion" }
            6 { "Periodo de gracia adicional" }
            default { "Desconocido ($($producto.LicenseStatus))" }
        }
        Write-Log "Producto: $($producto.Name)" -Tipo INFO
        Write-Log "Estado: $estadoTexto" -Tipo $(if ($producto.LicenseStatus -eq 1) { 'OK' } else { 'AVISO' })
        if ($producto.PartialProductKey) {
            Write-Log "Ultimos 5 caracteres de la clave: $($producto.PartialProductKey)" -Tipo INFO
        }
        Show-Aviso "Producto: $($producto.Name)`nEstado: $estadoTexto" "Estado de activacion"
    } catch {
        Write-Log "No se pudo consultar el estado de activacion: $($_.Exception.Message)" -Tipo ERROR
    }
}

# ---------------------------------------------------------------------------
#  HISTORIAL DE PANTALLAS AZULES (BSOD)
# ---------------------------------------------------------------------------

# Tabla de codigos STOP mas comunes: nombre y recomendacion practica.
$Script:TablaBugCheck = @{
    '0x0000000a' = @{ Nombre='IRQL_NOT_LESS_OR_EQUAL'; Recomendacion='Casi siempre un controlador defectuoso (a veces RAM). Actualiza los drivers, sobre todo de red y almacenamiento, y ejecuta un diagnostico de memoria.' }
    '0x0000001a' = @{ Nombre='MEMORY_MANAGEMENT'; Recomendacion='Relacionado con la memoria RAM. Ejecuta el Diagnostico de memoria de Windows; si persiste, prueba cambiando los modulos de RAM de slot o uno por uno.' }
    '0x0000001e' = @{ Nombre='KMODE_EXCEPTION_NOT_HANDLED'; Recomendacion='Un controlador incompatible o defectuoso. Revisa que se instalo o actualizo justo antes de la falla y actualizalo o revierte el cambio.' }
    '0x0000003b' = @{ Nombre='SYSTEM_SERVICE_EXCEPTION'; Recomendacion='Muy asociado al controlador de video. Actualiza el driver de tu tarjeta grafica y el resto de controladores recientes.' }
    '0x00000050' = @{ Nombre='PAGE_FAULT_IN_NONPAGED_AREA'; Recomendacion='Puede ser RAM defectuosa, disco con errores o un driver. Ejecuta Diagnostico de memoria de Windows y una comprobacion de disco (chkdsk).' }
    '0x0000007b' = @{ Nombre='INACCESSIBLE_BOOT_DEVICE'; Recomendacion='Windows no pudo acceder al disco de arranque. Revisa cambios recientes en BIOS (modo SATA/AHCI/RAID) o el estado del disco/controlador de almacenamiento.' }
    '0x0000007e' = @{ Nombre='SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'; Recomendacion='Un controlador genero un error no controlado. Actualiza todos los drivers, en especial video y red/WiFi.' }
    '0x0000009f' = @{ Nombre='DRIVER_POWER_STATE_FAILURE'; Recomendacion='Un driver no maneja bien la suspension/hibernacion. Actualiza controladores (especialmente red y chipset) y revisa la configuracion de energia.' }
    '0x000000c2' = @{ Nombre='BAD_POOL_CALLER'; Recomendacion='Un controlador manejo mal la memoria. Revisa drivers instalados recientemente y software de seguridad/antivirus de terceros.' }
    '0x000000d1' = @{ Nombre='DRIVER_IRQL_NOT_LESS_OR_EQUAL'; Recomendacion='Normalmente el controlador de red o WiFi. Actualiza el driver de tu adaptador de red y otros perifericos.' }
    '0x000000ef' = @{ Nombre='CRITICAL_PROCESS_DIED'; Recomendacion='Un proceso critico de Windows se cerro inesperadamente. Ejecuta Verificar archivos de sistema (SFC) y Reparar imagen de Windows (DISM), y revisa si hay malware.' }
    '0x000000f4' = @{ Nombre='CRITICAL_OBJECT_TERMINATION'; Recomendacion='Puede indicar fallo del disco duro/SSD. Revisa el estado del disco (S.M.A.R.T. con un programa del fabricante) y ejecuta chkdsk.' }
    '0x00000116' = @{ Nombre='VIDEO_TDR_FAILURE'; Recomendacion='La tarjeta de video dejo de responder. Reinstala el controlador de video; si haces overclock a la GPU, revierte la configuracion y revisa temperaturas.' }
    '0x00000124' = @{ Nombre='WHEA_UNCORRECTABLE_ERROR'; Recomendacion='Error de hardware detectado por el procesador (CPU, memoria o fuente de poder). Revisa temperaturas, revierte cualquier overclock y prueba la RAM.' }
    '0x00000133' = @{ Nombre='DPC_WATCHDOG_VIOLATION'; Recomendacion='Un controlador tardo demasiado en responder; suele ser el driver de almacenamiento (SSD/NVMe) o del chipset. Actualizalos desde la web del fabricante.' }
    '0x0000012b' = @{ Nombre='FAULTY_HARDWARE_CORRUPTED_PAGE'; Recomendacion='Fuerte indicio de hardware defectuoso (RAM o CPU). Ejecuta Diagnostico de memoria de Windows y revisa temperaturas / overclock.' }
}

function Get-InfoBugCheck {
    param([string]$Codigo)
    if ($Codigo) {
        $clave = $Codigo.ToLower()
        if ($Script:TablaBugCheck.ContainsKey($clave)) { return $Script:TablaBugCheck[$clave] }
    }
    return @{
        Nombre = if ($Codigo) { "Codigo no catalogado ($Codigo)" } else { "Codigo no identificado" }
        Recomendacion = "No esta en nuestra tabla de codigos comunes. Busca el codigo en el sitio de soporte de Microsoft, ejecuta Verificar archivos de sistema (SFC), actualiza todos los controladores y revisa la memoria RAM."
    }
}

function Get-HistorialBSOD {
    try {
        $eventos = Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001} -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'WER-SystemErrorReporting|Windows Error Reporting' -or $_.Message -match 'BugCheck' }
    } catch {
        return @()
    }
    $resultado = foreach ($e in $eventos) {
        $codigo = $null
        if ($e.Message -match '0x[0-9A-Fa-f]{8}') { $codigo = $Matches[0] }
        $info = Get-InfoBugCheck -Codigo $codigo
        [PSCustomObject]@{
            Fecha         = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
            Codigo        = if ($codigo) { $codigo } else { "Desconocido" }
            Nombre        = $info.Nombre
            Recomendacion = $info.Recomendacion
        }
    }
    return $resultado
}

function Accion-DiagnosticoMemoriaWindows {
    if (Show-Confirm "Se abrira el Diagnostico de memoria de Windows. El equipo se reiniciara para ejecutar la prueba. ¿Continuar?") {
        Write-Log "Iniciando Diagnostico de memoria de Windows (requiere reinicio)." -Tipo OK
        Start-Process "mdsched.exe"
    }
}

function Accion-AbrirCarpetaMinidump {
    $ruta = "$env:WINDIR\Minidump"
    if (Test-Path $ruta) {
        Start-Process explorer.exe -ArgumentList $ruta
        Write-Log "Carpeta de volcados de memoria abierta." -Tipo OK
    } else {
        Show-Aviso "No se encontro la carpeta de volcados de memoria ($ruta). Puede que Windows no este generando minidumps en este equipo." "Carpeta no encontrada"
    }
}

function Accion-ConfigVolcadoMemoria {
    Write-Log "Verificando configuracion de volcado de memoria..."
    try {
        $val = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "CrashDumpEnabled" -ErrorAction Stop
        $desc = switch ($val.CrashDumpEnabled) {
            0 { "Desactivado (Windows NO esta guardando volcados de memoria cuando ocurre un BSOD)" }
            1 { "Volcado completo" }
            2 { "Volcado de kernel" }
            3 { "Volcado pequeño (minidump)" }
            7 { "Volcado automatico (recomendado)" }
            default { "Valor desconocido ($($val.CrashDumpEnabled))" }
        }
        Write-Log "Configuracion actual: $desc" -Tipo OK
        if ($val.CrashDumpEnabled -eq 0) {
            if (Show-Confirm "Los volcados de memoria estan desactivados: no se puede diagnosticar a fondo la proxima pantalla azul. ¿Activar volcados automaticos ahora?") {
                if (-not (Requiere-Admin)) { return }
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "CrashDumpEnabled" -Value 7 -Type DWord
                Write-Log "Volcados de memoria activados (modo automatico)." -Tipo OK
            }
        }
    } catch {
        Write-Log "No se pudo leer la configuracion de volcado de memoria." -Tipo AVISO
    }
}

function Accion-AbrirMonitorConfiabilidad {
    Start-Process "perfmon.exe" -ArgumentList "/rel"
    Write-Log "Monitor de confiabilidad de Windows abierto (linea de tiempo de errores y cambios recientes)." -Tipo OK
}

function Accion-ExportarHistorialBSOD {
    try {
        $datos = Get-HistorialBSOD
        if ($datos.Count -eq 0) { Write-Log "No hay historial de BSOD para exportar." -Tipo AVISO; return }
        $destino = Join-Path $Script:ScriptDir "Historial_BSOD_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $lineas = foreach ($d in $datos) { "$($d.Fecha) | $($d.Codigo) | $($d.Nombre)`r`nRecomendacion: $($d.Recomendacion)`r`n" }
        ($lineas -join "`r`n") | Out-File -FilePath $destino -Encoding UTF8
        Write-Log "Historial exportado a: $destino" -Tipo OK
        if (Show-Confirm "¿Abrir el archivo exportado?") { Start-Process $destino }
    } catch {
        Write-Log "No se pudo exportar el historial: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-VerControladoresRecientes {
    Write-Log "Buscando controladores instalados/actualizados recientemente (para correlacionar con las BSOD)..."
    $todos = Get-TodosLosControladores
    $recientes = $todos | Where-Object { $_.Fecha -ne "Desconocida" } | Sort-Object Fecha -Descending | Select-Object -First 10
    if ($recientes) {
        Write-Log "Los 10 controladores con fecha mas reciente:" -Tipo OK
        foreach ($r in $recientes) { Write-Log " - $($r.Fecha) | $($r.Nombre) [$($r.Fabricante)]" }
    } else {
        Write-Log "No se pudo determinar la fecha de los controladores instalados." -Tipo AVISO
    }
}

function Cargar-DatosBSODTab {
    Write-Log "Buscando historial de pantallas azules en el registro de sucesos..."
    $datos = Get-HistorialBSOD
    $gridB = $window.FindName("GridBSODTab")
    $txtB = $window.FindName("TxtResumenBSODTab")
    if ($gridB) { $gridB.ItemsSource = $datos }
    if ($txtB) {
        $txtB.Text = if ($datos.Count -eq 0) {
            "No se encontraron pantallas azules registradas (o no se pudo leer el registro de sucesos)."
        } else {
            "Se encontraron $($datos.Count) pantalla(s) azul(es) registrada(s)."
        }
    }
    Write-Log "Busqueda de BSOD completada: $($datos.Count) encontrada(s)." -Tipo OK
}

# ---------------------------------------------------------------------------
#  DIAGNOSTICAR EQUIPO (hardware) + analisis opcional con IA
# ---------------------------------------------------------------------------

$Script:DiagLogIniciado = $false
function Write-DiagLog {
    param([string]$Mensaje)
    Write-Log $Mensaje -Tipo INFO
    $caja = $window.FindName("TxtDiagResultados")
    if ($caja) {
        if (-not $Script:DiagLogIniciado) {
            $caja.Clear()
            $Script:DiagLogIniciado = $true
        }
        $caja.AppendText("$Mensaje`r`n")
        $caja.ScrollToEnd()
    }
    # Write-Log siempre recibe -Tipo INFO desde aqui (para no romper el formato
    # del registro de diagnostico), asi que los fallos de las pruebas se
    # detectan por patrones de texto y se registran aparte para la pestaña de
    # Registro de errores.
    if ($Mensaje -match '(?i)no se pudo|no se pud[oe]|error|ATENCION|no se detect[oó]|no se encontr[oó]|fall[oó]|sin conexion') {
        try {
            $callStack = Get-PSCallStack
            $origen = if ($callStack.Count -gt 1 -and $callStack[1].FunctionName) { $callStack[1].FunctionName } else { "Prueba de diagnostico" }
            $Script:RegistroErrores.Add([PSCustomObject]@{
                Hora      = (Get-Date).ToString('HH:mm:ss')
                Tipo      = 'AVISO'
                Categoria = 'Prueba de diagnostico'
                Origen    = $origen
                Mensaje   = $Mensaje
            }) | Out-Null
        } catch {}
    }
}

# --- Gancho de teclado de bajo nivel (WH_KEYBOARD_LL) ---
# Se usa solo en la prueba de teclado, para poder detectar teclas especiales
# como Copilot (y, si el fabricante la reporta a Windows, Fn) que muchas
# veces no llegan como un Key normal de WPF. Captura el codigo de tecla
# virtual (vkCode) y el codigo de escaneo (scanCode) de cada tecla presionada
# en todo el sistema mientras la ventana de prueba esta abierta.
$Script:TipoTecladoHookListo = $false
function Ensure-TipoTecladoHook {
    if ($Script:TipoTecladoHookListo) { return }
    $codigo = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Diagnostics;

public static class DragonToolTecladoHook {
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private static IntPtr hookId = IntPtr.Zero;
    private static LowLevelKeyboardProc proc = HookCallback;
    private static Queue<uint[]> eventos = new Queue<uint[]>();

    public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public static void Instalar() {
        if (hookId != IntPtr.Zero) { return; }
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule) {
            hookId = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    public static void Desinstalar() {
        if (hookId == IntPtr.Zero) { return; }
        UnhookWindowsHookEx(hookId);
        hookId = IntPtr.Zero;
    }

    public static uint[] SacarSiguiente() {
        lock (eventos) {
            if (eventos.Count > 0) { return eventos.Dequeue(); }
        }
        return null;
    }

    public static void Limpiar() {
        lock (eventos) { eventos.Clear(); }
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            bool esBajada = (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN);
            bool esSubida = (wParam == (IntPtr)WM_KEYUP || wParam == (IntPtr)WM_SYSKEYUP);
            if (esBajada || esSubida) {
                KBDLLHOOKSTRUCT datos = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                // El cuarto valor indica si es una tecla que baja (1) o que sube (0),
                // para poder distinguir "recien pulsada" de "sigue sostenida". El
                // quinto valor es la marca de tiempo del propio hardware/driver del
                // teclado (milisegundos), no del momento en que PowerShell la lee de
                // la cola: se usa para medir con precision el intervalo real entre
                // pulsaciones de una misma tecla y asi detectar "rebote" (una sola
                // pulsada fisica que el interruptor manda como dos o mas).
                lock (eventos) { eventos.Enqueue(new uint[] { datos.vkCode, datos.scanCode, datos.flags, (uint)(esBajada ? 1 : 0), datos.time }); }
            }
        }
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoTecladoHookListo = $true
}

# Consulta en vivo a Windows (API nativa, no una tabla fija nuestra) de que
# caracter produce cada tecla fisica bajo la distribucion de teclado que el
# usuario tiene activa AHORA MISMO. Se identifica cada tecla fisica por su
# scanCode de hardware (el mismo valor "universal" que ya usa el gancho de
# bajo nivel para detectar pulsaciones, independiente del idioma), y se le
# pregunta a Windows que caracter le asigna la distribucion activa a esa
# posicion fisica. Asi el teclado en pantalla muestra el simbolo REAL de
# cada tecla sin importar si el usuario tiene Español Latinoamerica, España,
# Ingles EE.UU., u otra distribucion instalada: se detecta sola, no se
# adivina desde una lista fija de idiomas.
$Script:TipoTecladoLayoutListo = $false
function Ensure-TipoTecladoLayoutQuery {
    if ($Script:TipoTecladoLayoutListo) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class DragonToolTecladoLayout {
    private const uint MAPVK_VSC_TO_VK_EX = 3;

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKeyEx(uint uCode, uint uMapType, IntPtr dwhkl);

    [DllImport("user32.dll")]
    private static extern int ToUnicodeEx(uint wVirtKey, uint wScanCode, byte[] lpKeyState, StringBuilder pwszBuff, int cchBuff, uint wFlags, IntPtr dwhkl);

    private static string Traducir(int scanCode, IntPtr hkl, bool conMayuscula) {
        uint vk = MapVirtualKeyEx((uint)scanCode, MAPVK_VSC_TO_VK_EX, hkl);
        if (vk == 0) { return ""; }
        byte[] estado = new byte[256];
        if (conMayuscula) { estado[0x10] = 0x80; } // VK_SHIFT sostenido
        StringBuilder buffer = new StringBuilder(8);
        int r = ToUnicodeEx(vk, (uint)scanCode, estado, buffer, buffer.Capacity, 0, hkl);
        if (r < 0) {
            // Tecla muerta (acento combinable, como el acento agudo suelto
            // de algunas distribuciones en español): se vuelve a llamar para
            // limpiar el estado interno del driver y no dejarlo "colgado"
            // para la proxima tecla real que el usuario escriba, pero no se
            // muestra ningun simbolo para esta.
            buffer.Clear();
            ToUnicodeEx(vk, (uint)scanCode, estado, buffer, buffer.Capacity, 0, hkl);
            return "";
        }
        if (r <= 0) { return ""; }
        string s = buffer.ToString();
        foreach (char c in s) { if (char.IsControl(c)) { return ""; } }
        return s;
    }

    // Caracter base (sin Shift) que produce la tecla fisica de ese scanCode
    // bajo la distribucion "hkl" indicada.
    public static string ObtenerBase(int scanCode, IntPtr hkl) { return Traducir(scanCode, hkl, false); }

    // Caracter con Shift sostenido (el simbolo de arriba, por ejemplo el "!"
    // sobre el "1") que produce esa misma tecla fisica.
    public static string ObtenerMayus(int scanCode, IntPtr hkl) { return Traducir(scanCode, hkl, true); }
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoTecladoLayoutListo = $true
}

function Show-PruebaTeclado {
    # El boton "Probar teclado" abre el teclado virtual directamente, sin
    # ningun paso ni ventana de seleccion previa: la distribucion de teclado
    # (que caracter tiene cada tecla) se detecta automaticamente de Windows.
    Iniciar-PruebaTecladoVisual
}

function Iniciar-PruebaTecladoVisual {
    Write-DiagLog "=== TECLADO (prueba interactiva propia) ==="
    # Se pregunta ANTES de armar la ventana si el teclado tiene bloque
    # numerico: muchas laptops (sobre todo las de 13-14") no lo traen, y
    # mostrarlo igual dejaba un bloque de teclas que esa persona jamas iba a
    # poder probar (siempre se quedaba sin marcar, pareciendo una falla).
    $tieneNumerico = Show-Confirm -Mensaje "¿Tu teclado tiene bloque numerico (el grupo de teclas de numeros aparte, normalmente a la derecha del teclado)?" -Titulo "Prueba de teclado - The Dragon Tool"
    if ($tieneNumerico) {
        Write-DiagLog "Se abrira un teclado virtual completo (con numerico): pulsa teclas fisicas y observa si se iluminan en pantalla."
    } else {
        Write-DiagLog "Se abrira un teclado virtual completo (sin numerico): pulsa teclas fisicas y observa si se iluminan en pantalla."
    }
    try {
        # --- Distribucion, fila por fila ------------------------------------
        # Bloque principal, como el de una laptop real con teclado ISO en
        # español: incluye la tecla adicional "<>" junto al Shift izquierdo
        # (VK_OEM_102), presente en casi toda laptop en español y que antes
        # faltaba por completo en la distribucion de prueba.
        $filas = @(
            @(@{L='Esc';K='Escape'},@{L='F1';K='F1'},@{L='F2';K='F2'},@{L='F3';K='F3'},@{L='F4';K='F4'},@{L='F5';K='F5'},@{L='F6';K='F6'},@{L='F7';K='F7'},@{L='F8';K='F8'},@{L='F9';K='F9'},@{L='F10';K='F10'},@{L='F11';K='F11'},@{L='F12';K='F12'}),
            @(@{L='`';K='OemTilde'},@{L='1';K='D1'},@{L='2';K='D2'},@{L='3';K='D3'},@{L='4';K='D4'},@{L='5';K='D5'},@{L='6';K='D6'},@{L='7';K='D7'},@{L='8';K='D8'},@{L='9';K='D9'},@{L='0';K='D0'},@{L='-';K='OemMinus'},@{L='=';K='OemPlus'},@{L='Backspace';K='Back';W=2}),
            @(@{L='Tab';K='Tab';W=1.5},@{L='Q';K='Q'},@{L='W';K='W'},@{L='E';K='E'},@{L='R';K='R'},@{L='T';K='T'},@{L='Y';K='Y'},@{L='U';K='U'},@{L='I';K='I'},@{L='O';K='O'},@{L='P';K='P'},@{L='[';K='OemOpenBrackets'},@{L=']';K='OemCloseBrackets'},@{L='\';K='OemBackslash';W=1.5}),
            @(@{L='Caps';K='CapsLock';W=1.75},@{L='A';K='A'},@{L='S';K='S'},@{L='D';K='D'},@{L='F';K='F'},@{L='G';K='G'},@{L='H';K='H'},@{L='J';K='J'},@{L='K';K='K'},@{L='L';K='L'},@{L=';';K='OemSemicolon'},@{L="'";K='OemQuotes'},@{L='Enter';K='Return';W=2.25}),
            @(@{L='Shift';K='LeftShift';W=1.25},@{L='<>';K='OemAngleBracket102'},@{L='Z';K='Z'},@{L='X';K='X'},@{L='C';K='C'},@{L='V';K='V'},@{L='B';K='B'},@{L='N';K='N'},@{L='M';K='M'},@{L=',';K='OemComma'},@{L='.';K='OemPeriod'},@{L='/';K='OemQuestion'},@{L='Shift';K='RightShift';W=2.75}),
            @(@{L='Ctrl';K='LeftCtrl';W=1.4},@{L='Win';K='LWin';W=1.2},@{L='Alt';K='LeftAlt';W=1.2},@{L='Espacio';K='Space';W=6},@{L='Alt';K='RightAlt';W=1.2},@{L='Win';K='RWin';W=1.2},@{L='Menu';K='Apps';W=1.2},@{L='Ctrl';K='RightCtrl';W=1.4})
        )

        # Columna de navegacion + flechas, compacta y pegada al bloque
        # principal (como en una laptop de 15-16" con numerico integrado):
        # Ins/Supr, Inicio/Fin y RePag/AvPag en pares de 2 columnas; las
        # flechas en "T invertida" (arriba solo ↑, centrada sobre las otras
        # tres abajo), igual que en una laptop real.
        $filaSistema = @(@{L='PrtScn';K='PrintScreen';W=1.3},@{L='ScrLk';K='Scroll';W=1.3},@{L='Pausa';K='Pause';W=1.3})
        $filaNavGrid1 = @(@{L='Ins';K='Insert'},@{L='Supr';K='Delete'})
        $filaNavGrid2 = @(@{L='Inicio';K='Home'},@{L='Fin';K='End'})
        $filaNavGrid3 = @(@{L='RePag';K='Prior'},@{L='AvPag';K='Next'})
        $filaFlechasArriba = @(@{L='';K=$null},@{L='↑';K='Up'},@{L='';K=$null})
        $filaFlechasAbajo = @(@{L='←';K='Left'},@{L='↓';K='Down'},@{L='→';K='Right'})

        # Bloque numerico completo, pegado a la derecha de la columna de
        # navegacion. El Enter del numerico usa su PROPIO nombre interno
        # (NumPadEnter) en vez de compartir "Return" con el Enter principal:
        # son teclas fisicas distintas y el gancho las distingue por el bit
        # "extendida" (ver Resolver-NombreTeclaFisica), asi que antes de este
        # cambio pulsar solo una de las dos encendia las dos en pantalla.
        $filaNumpad1 = @(@{L='NumLk';K='NumLock'},@{L='Num/';K='Divide'},@{L='Num*';K='Multiply'},@{L='Num-';K='Subtract'})
        $filaNumpad2 = @(@{L='Num7';K='NumPad7'},@{L='Num8';K='NumPad8'},@{L='Num9';K='NumPad9'},@{L='Num+';K='Add'})
        $filaNumpad3 = @(@{L='Num4';K='NumPad4'},@{L='Num5';K='NumPad5'},@{L='Num6';K='NumPad6'})
        $filaNumpad4 = @(@{L='Num1';K='NumPad1'},@{L='Num2';K='NumPad2'},@{L='Num3';K='NumPad3'},@{L='NumEnter';K='NumPadEnter';W=1.4})
        $filaNumpad5 = @(@{L='Num0';K='NumPad0';W=2.1},@{L='Num.';K='Decimal'})

        # --- Deteccion automatica de la distribucion de teclado --------------
        # Se detecta la distribucion realmente activa en Windows (idioma +
        # variante de teclado que el usuario tiene puesta ahora mismo, la
        # misma que usa para escribir) y se le pregunta a Windows, tecla por
        # tecla fisica, que caracter le corresponde a cada una en esa
        # distribucion. Solo se consulta para las teclas que producen un
        # caracter (letras, numeros, simbolos): las de funcion, navegacion,
        # modificadores y numerico no cambian de un idioma a otro y se dejan
        # con su etiqueta fija.
        Ensure-TipoTecladoLayoutQuery
        $idiomaDetectado = [System.Windows.Forms.InputLanguage]::CurrentInputLanguage
        $hklActivo = $idiomaDetectado.Handle
        $nombreDistribucion = "$($idiomaDetectado.Culture.DisplayName) - $($idiomaDetectado.LayoutName)"

        # Mapa de tecla fisica -> scanCode de hardware "Set 1" estandar (el
        # mismo esquema universal que ya usa el gancho de bajo nivel), para
        # cada tecla del bloque principal que produce un caracter.
        $scMapaCaracteres = @{
            'OemTilde'=0x29; 'D1'=0x02; 'D2'=0x03; 'D3'=0x04; 'D4'=0x05; 'D5'=0x06; 'D6'=0x07; 'D7'=0x08; 'D8'=0x09; 'D9'=0x0A; 'D0'=0x0B; 'OemMinus'=0x0C; 'OemPlus'=0x0D
            'Q'=0x10; 'W'=0x11; 'E'=0x12; 'R'=0x13; 'T'=0x14; 'Y'=0x15; 'U'=0x16; 'I'=0x17; 'O'=0x18; 'P'=0x19; 'OemOpenBrackets'=0x1A; 'OemCloseBrackets'=0x1B; 'OemBackslash'=0x2B
            'A'=0x1E; 'S'=0x1F; 'D'=0x20; 'F'=0x21; 'G'=0x22; 'H'=0x23; 'J'=0x24; 'K'=0x25; 'L'=0x26; 'OemSemicolon'=0x27; 'OemQuotes'=0x28
            'OemAngleBracket102'=0x56; 'Z'=0x2C; 'X'=0x2D; 'C'=0x2E; 'V'=0x2F; 'B'=0x30; 'N'=0x31; 'M'=0x32; 'OemComma'=0x33; 'OemPeriod'=0x34; 'OemQuestion'=0x35
        }
        $teclasSoloLetra = @('Q','W','E','R','T','Y','U','I','O','P','A','S','D','F','G','H','J','K','L','Z','X','C','V','B','N','M')
        foreach ($fila in $filas) {
            foreach ($tecla in $fila) {
                if (-not $scMapaCaracteres.ContainsKey($tecla.K)) { continue }
                $sc = $scMapaCaracteres[$tecla.K]
                $base = [DragonToolTecladoLayout]::ObtenerBase($sc, $hklActivo)
                if (-not $base) { continue }   # Sin caracter en esta distribucion: se deja la etiqueta original.
                if ($teclasSoloLetra -contains $tecla.K) {
                    # Las letras solo muestran su caracter en mayuscula, como
                    # en un teclado real (no hace falta mostrar tambien el
                    # shift, que es la misma letra en mayuscula).
                    $tecla.L = $base.ToUpperInvariant()
                } else {
                    $mayus = [DragonToolTecladoLayout]::ObtenerMayus($sc, $hklActivo)
                    if ($mayus -and $mayus -ne $base) {
                        # Simbolo de Shift arriba, caracter base abajo, igual
                        # que se ve impreso en una tecla fisica real.
                        $tecla.L = "$mayus`n$base"
                    } else {
                        $tecla.L = $base
                    }
                }
            }
        }

        Ensure-TipoTecladoHook

        # --- Ventana ---------------------------------------------------------
        [xml]$xamlTec = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Prueba de teclado - The Dragon Tool" SizeToContent="WidthAndHeight" MinWidth="900" MinHeight="440" WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <DockPanel Margin="16">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Text="Pulsa las teclas de tu teclado fisico; se iluminaran aqui en tiempo real. Azul = tecla ya probada. Amarillo = la tecla sigue sostenida ahora mismo." Foreground="White" Margin="0,0,0,6" TextWrapping="Wrap"/>
    <TextBlock x:Name="TxtDistribucion" DockPanel.Dock="Top" Text="Distribucion detectada: (detectando...)" Foreground="#C9A6FF" FontSize="11" Margin="0,0,0,8" TextWrapping="Wrap"/>
    <TextBlock x:Name="TxtUltimaTecla" DockPanel.Dock="Top" Text="Ultima tecla: (ninguna)" Foreground="#66AEFF" FontWeight="Bold" Margin="0,0,0,4"/>
    <TextBlock x:Name="TxtProbadas" DockPanel.Dock="Top" Text="Teclas probadas: 0 / 0" Foreground="#8FE38F" FontWeight="Bold" Margin="0,0,0,4"/>
    <TextBlock x:Name="TxtCodigoEspecial" DockPanel.Dock="Top" Text="Ultimo codigo detectado: (ninguno)" Foreground="#7C93BD" FontSize="11" Margin="0,0,0,6"/>
    <TextBlock x:Name="TxtRebotes" DockPanel.Dock="Top" Text="" Foreground="#FF6B6B" FontWeight="Bold" Margin="0,0,0,10" TextWrapping="Wrap"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="BtnReporteRebotes" Content="Reporte de errores" Width="150" Margin="0,0,8,0"/>
      <Button x:Name="BtnReiniciarTeclado" Content="Reiniciar colores" Width="130" Margin="0,0,8,0"/>
      <Button x:Name="BtnCerrarTeclado" Content="Cerrar" Width="100"/>
    </StackPanel>
    <StackPanel x:Name="PanelTeclado" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </DockPanel>
</Window>
"@
        $readerTec = New-Object System.Xml.XmlNodeReader $xamlTec
        $winTec = [Windows.Markup.XamlReader]::Load($readerTec)
        Iniciar-EfectosNeon -Ventana $winTec
        $panelTeclado = $winTec.FindName("PanelTeclado")
        $txtDistribucion = $winTec.FindName("TxtDistribucion")
        $txtUltimaTecla = $winTec.FindName("TxtUltimaTecla")
        $txtProbadas = $winTec.FindName("TxtProbadas")
        $txtCodigoEspecial = $winTec.FindName("TxtCodigoEspecial")
        $txtRebotes = $winTec.FindName("TxtRebotes")
        $txtDistribucion.Text = "Distribucion de teclado detectada: $nombreDistribucion"

        $mapaTeclas = @{}
        $mapaColorBase = @{}
        # Colores con canal alfa (2 primeros digitos del hex) para el efecto
        # de "vidrio esmerilado": se deja ver un poco el fondo de la tarjeta
        # detras de cada tecla en vez de un color solido plano.
        $colorNormal = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CC181F2E")
        $colorAcento = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CC212B45")
        $colorPresionado = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E62F7CF6")
        $colorMantenida = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E6F5C518")
        $bordeNormal = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#40FFFFFF")

        # --- Funciones auxiliares --------------------------------------------
        # Nuevo-FondoTecla e Iluminar-Tecla se declaran Global: y reciben TODO
        # por parametro (nada de closures sobre variables externas) porque se
        # llaman tanto desde codigo normal como desde dentro de scriptblocks
        # .GetNewClosure() (el timer del gancho de teclado, el boton de
        # reinicio). .GetNewClosure() desconecta el scriptblock de la funcion
        # que lo creo: solo arrastra el VALOR de las variables locales
        # capturadas, nunca las funciones normales del scope padre. Llamar a
        # una funcion normal (no Global) desde dentro de un .GetNewClosure()
        # falla en silencio ("no se reconoce como nombre de cmdlet"): asi fue
        # como en una version anterior de esta prueba ninguna tecla se
        # iluminaba pese a que el gancho si detectaba cada pulsacion.
        function Global:Nuevo-FondoTecla {
            param($ColorBase)
            $degradado = New-Object System.Windows.Media.LinearGradientBrush
            $degradado.StartPoint = [System.Windows.Point]::new(0, 0)
            $degradado.EndPoint = [System.Windows.Point]::new(0, 1)
            $paradaClara = New-Object System.Windows.Media.GradientStop
            # Usa el mismo canal alfa del color base (no 255 fijo) para que el
            # degradado mantenga el efecto de vidrio en toda la tecla.
            $paradaClara.Color = [System.Windows.Media.Color]::FromArgb($ColorBase.Color.A, [Math]::Min(255, $ColorBase.Color.R + 18), [Math]::Min(255, $ColorBase.Color.G + 18), [Math]::Min(255, $ColorBase.Color.B + 20))
            $paradaClara.Offset = 0
            $paradaOscura = New-Object System.Windows.Media.GradientStop
            $paradaOscura.Color = $ColorBase.Color
            $paradaOscura.Offset = 1
            $degradado.GradientStops.Add($paradaClara) | Out-Null
            $degradado.GradientStops.Add($paradaOscura) | Out-Null
            return $degradado
        }

        function Global:Iluminar-Tecla {
            # Azul (colorPresionado) = tecla ya probada (se pulso al menos una vez).
            # Amarillo (colorMantenida) = la tecla sigue sostenida en este momento.
            param($MapaTeclas, [string]$NombreTecla, $Color)
            if ($MapaTeclas.ContainsKey($NombreTecla)) {
                foreach ($b in $MapaTeclas[$NombreTecla]) { $b.Background = $Color }
            }
        }

        # Traduce un codigo VK (+ scanCode + bit "extendida") del gancho de
        # bajo nivel al nombre interno de tecla que usamos como clave en
        # $mapaTeclas. Global: y sin depender de nada del scope externo
        # (mismo motivo que las funciones de arriba: se llama desde dentro de
        # .GetNewClosure()). KeyInterop.KeyFromVirtualKey() por si solo NO
        # basta para identificar todas las teclas fisicas, por 4 motivos
        # reales de Windows:
        #  - Shift: el gancho de bajo nivel reporta SIEMPRE el VK generico
        #    (0x10) tanto para el Shift izquierdo como el derecho; solo el
        #    scanCode los diferencia (0x2A=izquierdo, 0x36=derecho).
        #  - Numerico: las teclas 7,8,9,4,5,6,1,2,3,0,. cambian de VK segun
        #    el estado de Bloq Num (con Bloq Num apagado mandan el mismo VK
        #    que Inicio/Fin/RePag/AvPag/flechas/Supr). El scanCode de esas
        #    teclas fisicas nunca cambia, y el bit "extendida" (presente
        #    siempre en las teclas de navegacion reales y nunca en las del
        #    numerico) permite distinguirlas sin importar Bloq Num.
        #  - Enter: el Enter principal y el del numerico comparten el mismo
        #    VK (0x0D); el del numerico siempre llega marcado como
        #    "extendida" y el principal nunca, asi que el bit "extendida" los
        #    separa en dos teclas fisicas distintas (Return / NumPadEnter).
        #  - Tecla "<>" adicional (VK_OEM_102, 0xE2): presente en casi toda
        #    laptop en español junto al Shift izquierdo; se resuelve aparte
        #    porque KeyInterop no siempre la reconoce.
        function Global:Resolver-NombreTeclaFisica {
            # Traduce un scanCode de hardware (+ el bit "extendida") del
            # gancho de bajo nivel al nombre interno de tecla fisica que
            # usamos como clave en $mapaTeclas. USA EL SCANCODE COMO FUENTE
            # PRINCIPAL DE VERDAD, NO el VK. Motivo real (el motivo por el
            # que "algunas teclas" seguian sin marcar en algunas maquinas):
            # el VK de las letras y numeros SI es fijo por posicion sin
            # importar la distribucion de teclado activa, pero el VK de las
            # teclas OEM/simbolos (guion, igual, corchetes, punto y coma,
            # comillas, acento, coma, punto, barra, barra invertida, etc.)
            # LO ASIGNA CADA DISTRIBUCION DE TECLADO A SU MANERA: Español
            # (Latinoamerica), Español (España) e Ingles (EE.UU.) pueden
            # asignarle un VK distinto a la MISMA posicion fisica. Antes
            # esta funcion resolvia esas teclas con
            # KeyInterop.KeyFromVirtualKey(vk), que en una distribucion
            # distinta a la que se probo podia devolver un nombre que no
            # coincidia con ninguna tecla del layout, y esa tecla fisica
            # nunca se iluminaba aunque el gancho si la detectara. El
            # scanCode identifica la posicion fisica de la tecla sin
            # importar que caracter o VK le asigne la distribucion activa,
            # asi que es la unica forma fiable de que CADA tecla marque sin
            # importar el idioma/distribucion de teclado que tenga el
            # usuario. De paso, esto resuelve de forma mas directa (con dos
            # tablas separadas por el bit "extendida") los mismos casos que
            # antes se manejaban con reglas sueltas: Shift/Ctrl/Alt
            # izquierdo-derecho, Enter principal vs Enter del numerico, y el
            # numerico sin importar el estado de Bloq Num.
            param([int]$Vk, [int]$Sc, [bool]$EsExtendida)

            # Caso especial: la tecla Pausa manda una secuencia de scanCode
            # muy irregular en el hardware real (distinta a todas las demas
            # teclas) que en algunos equipos puede llegar a coincidir con el
            # scanCode de Bloq Num; su VK (0x13) en cambio es fijo y no
            # depende de la distribucion, asi que se resuelve aparte antes
            # de consultar la tabla de scanCodes.
            if ($Vk -eq 0x13) { return 'Pause' }

            $scNormal = @{
                0x01='Escape'
                0x02='D1'; 0x03='D2'; 0x04='D3'; 0x05='D4'; 0x06='D5'; 0x07='D6'; 0x08='D7'; 0x09='D8'; 0x0A='D9'; 0x0B='D0'
                0x0C='OemMinus'; 0x0D='OemPlus'; 0x0E='Back'
                0x0F='Tab'; 0x10='Q'; 0x11='W'; 0x12='E'; 0x13='R'; 0x14='T'; 0x15='Y'; 0x16='U'; 0x17='I'; 0x18='O'; 0x19='P'
                0x1A='OemOpenBrackets'; 0x1B='OemCloseBrackets'; 0x1C='Return'
                0x1D='LeftCtrl'
                0x1E='A'; 0x1F='S'; 0x20='D'; 0x21='F'; 0x22='G'; 0x23='H'; 0x24='J'; 0x25='K'; 0x26='L'
                0x27='OemSemicolon'; 0x28='OemQuotes'; 0x29='OemTilde'
                0x2A='LeftShift'
                0x2B='OemBackslash'
                0x2C='Z'; 0x2D='X'; 0x2E='C'; 0x2F='V'; 0x30='B'; 0x31='N'; 0x32='M'
                0x33='OemComma'; 0x34='OemPeriod'; 0x35='OemQuestion'
                0x36='RightShift'
                0x37='Multiply'
                0x38='LeftAlt'
                0x39='Space'
                0x3A='CapsLock'
                0x3B='F1'; 0x3C='F2'; 0x3D='F3'; 0x3E='F4'; 0x3F='F5'; 0x40='F6'; 0x41='F7'; 0x42='F8'; 0x43='F9'; 0x44='F10'
                0x45='NumLock'
                0x46='Scroll'
                0x47='NumPad7'; 0x48='NumPad8'; 0x49='NumPad9'; 0x4A='Subtract'
                0x4B='NumPad4'; 0x4C='NumPad5'; 0x4D='NumPad6'; 0x4E='Add'
                0x4F='NumPad1'; 0x50='NumPad2'; 0x51='NumPad3'; 0x52='NumPad0'; 0x53='Decimal'
                0x56='OemAngleBracket102'
                0x57='F11'; 0x58='F12'
            }
            $scExtendida = @{
                0x1C='NumPadEnter'; 0x1D='RightCtrl'; 0x35='Divide'; 0x37='PrintScreen'; 0x38='RightAlt'
                0x47='Home'; 0x48='Up'; 0x49='Prior'; 0x4B='Left'; 0x4D='Right'; 0x4F='End'; 0x50='Down'; 0x51='Next'
                0x52='Insert'; 0x53='Delete'; 0x5B='LWin'; 0x5C='RWin'; 0x5D='Apps'
            }

            $tabla = if ($EsExtendida) { $scExtendida } else { $scNormal }
            if ($tabla.ContainsKey($Sc)) { return $tabla[$Sc] }

            # Red de seguridad por si llega una tecla fuera de la tabla de
            # arriba (por ejemplo una tecla multimedia de algun fabricante):
            # se intenta resolver por VK como ultimo recurso.
            try {
                $claveEnum = [System.Windows.Input.KeyInterop]::KeyFromVirtualKey($Vk)
                if ($claveEnum -ne [System.Windows.Input.Key]::None) { return $claveEnum.ToString() }
            } catch {}
            return $null
        }

        function Agregar-FilaTeclado {
            # No es Global: solo se llama de forma sincrona mientras se arma
            # el teclado (nunca desde dentro de un .GetNewClosure()), asi que
            # puede quedarse como funcion normal.
            # $Estilo 'acento' tine las teclas que no son letras/numeros
            # (funcion, modificadores, flechas, navegacion, operadores del
            # numerico) para que la distribucion se lea mejor de un vistazo.
            param($Fila, $Panel, $Estilo = 'normal')
            $filaPanel = New-Object System.Windows.Controls.StackPanel
            $filaPanel.Orientation = "Horizontal"
            $filaPanel.HorizontalAlignment = "Center"
            $filaPanel.Margin = "0,3,0,3"
            $colorBase = if ($Estilo -eq 'acento') { $colorAcento } else { $colorNormal }
            foreach ($tecla in $Fila) {
                $ancho = 46
                if ($tecla.W) { $ancho = 46 * [double]$tecla.W }
                $border = New-Object System.Windows.Controls.Border
                $border.Width = $ancho
                $border.Height = 40
                $border.Margin = "2.5"
                if ($null -eq $tecla.K) {
                    # Celda vacia (espaciador invisible): solo se usa para armar
                    # la forma de "T invertida" de las flechas, como en una
                    # laptop real (la flecha arriba queda centrada sobre "abajo").
                    $border.Background = [System.Windows.Media.Brushes]::Transparent
                    $filaPanel.Children.Add($border) | Out-Null
                    continue
                }
                $border.CornerRadius = 14
                $border.Background = Nuevo-FondoTecla -ColorBase $colorBase
                $border.BorderBrush = $bordeNormal
                $border.BorderThickness = 1.2
                $sombra = New-Object System.Windows.Media.Effects.DropShadowEffect
                $sombra.Color = [System.Windows.Media.Colors]::Black
                $sombra.Direction = 270
                $sombra.ShadowDepth = 1.5
                $sombra.BlurRadius = 5
                $sombra.Opacity = 0.4
                $border.Effect = $sombra
                $txt = New-Object System.Windows.Controls.TextBlock
                $txt.Text = $tecla.L
                $txt.Foreground = [System.Windows.Media.Brushes]::White
                $txt.FontSize = 11
                $txt.FontWeight = "SemiBold"
                $txt.HorizontalAlignment = "Center"
                $txt.VerticalAlignment = "Center"
                $txt.TextAlignment = "Center"
                $border.Child = $txt
                $filaPanel.Children.Add($border) | Out-Null
                # Se guarda una LISTA de bordes por cada tecla (no un solo
                # borde): es una red de seguridad por si en el futuro dos
                # teclas fisicas distintas volvieran a compartir el mismo
                # nombre resuelto (como pasaba antes con Enter/NumEnter); con
                # una lista se iluminan todos los bordes que correspondan.
                if (-not $mapaTeclas.ContainsKey($tecla.K)) { $mapaTeclas[$tecla.K] = New-Object System.Collections.Generic.List[object] }
                $mapaTeclas[$tecla.K].Add($border) | Out-Null
                $mapaColorBase[$tecla.K] = $colorBase
            }
            $Panel.Children.Add($filaPanel) | Out-Null
        }

        function Nueva-Tarjeta {
            # No es Global: se llama de forma sincrona mientras se arma el
            # teclado, nunca desde dentro de un .GetNewClosure().
            param($Contenido)
            $tarjeta = New-Object System.Windows.Controls.Border
            $tarjeta.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D9141A28")
            $tarjeta.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#40FFFFFF")
            $tarjeta.BorderThickness = 1
            $tarjeta.CornerRadius = 20
            $tarjeta.Padding = 18
            $sombraTarjeta = New-Object System.Windows.Media.Effects.DropShadowEffect
            $sombraTarjeta.Color = [System.Windows.Media.Colors]::Black
            $sombraTarjeta.Direction = 270
            $sombraTarjeta.ShadowDepth = 2
            $sombraTarjeta.BlurRadius = 10
            $sombraTarjeta.Opacity = 0.35
            $tarjeta.Effect = $sombraTarjeta
            $tarjeta.Child = $Contenido
            return $tarjeta
        }

        # --- Construccion del teclado -----------------------------------------
        # Todo el teclado (bloque principal + navegacion/flechas + numerico)
        # se arma dentro de UNA sola tarjeta, pegado entre si, para que se
        # vea como el cuerpo compacto de una laptop real con numerico
        # integrado. La fila de funcion y la de modificadores/espacio llevan
        # el color de acento para resaltar, como en un teclado real.
        $panelPrincipal = New-Object System.Windows.Controls.StackPanel
        for ($i = 0; $i -lt $filas.Count; $i++) {
            $estiloFila = if ($i -eq 0 -or $i -eq ($filas.Count - 1)) { 'acento' } else { 'normal' }
            Agregar-FilaTeclado -Fila $filas[$i] -Panel $panelPrincipal -Estilo $estiloFila
        }

        $panelNavFlechas = New-Object System.Windows.Controls.StackPanel
        $panelNavFlechas.Margin = "14,0,0,0"
        $panelNavFlechas.VerticalAlignment = "Top"
        Agregar-FilaTeclado -Fila $filaSistema -Panel $panelNavFlechas -Estilo 'acento'
        Agregar-FilaTeclado -Fila $filaNavGrid1 -Panel $panelNavFlechas -Estilo 'acento'
        Agregar-FilaTeclado -Fila $filaNavGrid2 -Panel $panelNavFlechas -Estilo 'acento'
        Agregar-FilaTeclado -Fila $filaNavGrid3 -Panel $panelNavFlechas -Estilo 'acento'
        $espaciadorFlechas = New-Object System.Windows.Controls.Border
        $espaciadorFlechas.Height = 14
        $panelNavFlechas.Children.Add($espaciadorFlechas) | Out-Null
        Agregar-FilaTeclado -Fila $filaFlechasArriba -Panel $panelNavFlechas -Estilo 'acento'
        Agregar-FilaTeclado -Fila $filaFlechasAbajo -Panel $panelNavFlechas -Estilo 'acento'

        # El bloque numerico solo se arma y se agrega si el usuario confirmo
        # que su teclado lo trae: si no, ni se dibuja ni sus teclas se
        # registran en $mapaTeclas, para que no quede un bloque muerto que
        # nunca se puede marcar ni cuente en el contador de "teclas probadas".
        if ($tieneNumerico) {
            $panelNumerico = New-Object System.Windows.Controls.StackPanel
            $panelNumerico.Margin = "14,0,0,0"
            $panelNumerico.VerticalAlignment = "Top"
            Agregar-FilaTeclado -Fila $filaNumpad1 -Panel $panelNumerico -Estilo 'acento'
            foreach ($fila in @($filaNumpad2, $filaNumpad3, $filaNumpad4, $filaNumpad5)) {
                Agregar-FilaTeclado -Fila $fila -Panel $panelNumerico -Estilo 'normal'
            }
        }

        $panelConjunto = New-Object System.Windows.Controls.StackPanel
        $panelConjunto.Orientation = "Horizontal"
        $panelConjunto.Children.Add($panelPrincipal) | Out-Null
        $panelConjunto.Children.Add($panelNavFlechas) | Out-Null
        if ($tieneNumerico) { $panelConjunto.Children.Add($panelNumerico) | Out-Null }
        $panelTeclado.Children.Add((Nueva-Tarjeta -Contenido $panelConjunto)) | Out-Null

        $totalTeclas = $mapaTeclas.Keys.Count
        $txtProbadas.Text = "Teclas probadas: 0 / $totalTeclas"

        # --- Deteccion ----------------------------------------------------
        [DragonToolTecladoHook]::Limpiar()
        [DragonToolTecladoHook]::Instalar()
        # $teclasActivas guarda el NOMBRE resuelto (no el VK crudo) de las
        # teclas sostenidas ahora mismo. Usar el nombre resuelto evita que
        # dos teclas fisicas distintas que comparten VK (por ejemplo Shift
        # izquierdo/derecho, ambas VK 0x10) se confundan entre si al sostener
        # una y pulsar la otra: con el VK crudo, sostener la izquierda y
        # tocar la derecha marcaba la derecha como "ya sostenida" sin nunca
        # mostrarla en azul ni contarla como probada.
        $teclasActivas = New-Object 'System.Collections.Generic.HashSet[string]'
        $teclasProbadas = New-Object 'System.Collections.Generic.HashSet[string]'

        # --- Deteccion de "rebote" (fallo de hardware) ------------------
        # Un interruptor de tecla desgastado o con suciedad puede mandar la
        # señal de pulsacion DOS (o mas) veces por cada pulsada fisica real.
        # Se detecta comparando, para cada tecla, cuanto tiempo real de
        # hardware paso entre que se SOLTO y que se volvio a PULSAR: nadie
        # suelta y vuelve a presionar la misma tecla a proposito en unos
        # pocos milisegundos, asi que un intervalo menor a $umbralReboteMs
        # casi siempre significa que fue el mismo contacto fisico "rebotando"
        # electricamente, no dos pulsaciones reales de la persona. Se usa la
        # marca de tiempo que manda el propio driver del teclado (no el
        # momento en que PowerShell procesa la cola), para que sea precisa
        # de verdad sin importar cada cuanto corre este timer.
        $umbralReboteMs = 80
        $ultimoLevantadaMs = @{}
        $registroRebotes = @{}

        $timerEspecial = New-Object System.Windows.Threading.DispatcherTimer
        $timerEspecial.Interval = [TimeSpan]::FromMilliseconds(50)
        $timerEspecial.Add_Tick({
            $datos = $null
            while ($null -ne ($datos = [DragonToolTecladoHook]::SacarSiguiente())) {
                $vk = [int]$datos[0]
                $sc = [int]$datos[1]
                $flags = [int]$datos[2]
                $esExtendida = (($flags -band 0x01) -eq 0x01)
                $esBajada = ([int]$datos[3] -eq 1)
                $tiempo = [uint32]$datos[4]
                # Se iluminan las teclas usando el gancho global de bajo
                # nivel, nunca los eventos KeyDown/KeyUp propios de WPF: la
                # ventana de la prueba no siempre queda como ventana activa
                # de Windows (grabacion de pantalla, otra ventana encima, el
                # foco quedandose en la consola de PowerShell, etc), y en
                # esos casos WPF nunca recibe el evento de teclado aunque el
                # gancho global si detecta cada pulsacion. El gancho no
                # depende del foco, asi que es la unica fuente de verdad.
                $nombreTecla = Resolver-NombreTeclaFisica -Vk $vk -Sc $sc -EsExtendida $esExtendida
                if ($nombreTecla -and $mapaTeclas.ContainsKey($nombreTecla)) {
                    if ($esBajada) {
                        if ($teclasActivas.Contains($nombreTecla)) {
                            Iluminar-Tecla -MapaTeclas $mapaTeclas -NombreTecla $nombreTecla -Color $colorMantenida
                        } else {
                            # Rebote: esta misma tecla ya estaba SUELTA (no
                            # sostenida) y se acaba de soltar hace muy poco.
                            if ($ultimoLevantadaMs.ContainsKey($nombreTecla)) {
                                $intervalo = $tiempo - $ultimoLevantadaMs[$nombreTecla]
                                if ($intervalo -lt $umbralReboteMs) {
                                    if (-not $registroRebotes.ContainsKey($nombreTecla)) {
                                        $registroRebotes[$nombreTecla] = [PSCustomObject]@{ Conteo = 0; MenorIntervalo = $umbralReboteMs }
                                    }
                                    $registroRebotes[$nombreTecla].Conteo++
                                    if ($intervalo -lt $registroRebotes[$nombreTecla].MenorIntervalo) {
                                        $registroRebotes[$nombreTecla].MenorIntervalo = $intervalo
                                    }
                                    $nombresConRebote = ($registroRebotes.Keys | Sort-Object) -join ", "
                                    $txtRebotes.Text = "Posible falla de hardware (rebote) detectada en: $nombresConRebote -- usa 'Reporte de errores' para ver el detalle."
                                }
                            }
                            $teclasActivas.Add($nombreTecla) | Out-Null
                            Iluminar-Tecla -MapaTeclas $mapaTeclas -NombreTecla $nombreTecla -Color $colorPresionado
                            if ($teclasProbadas.Add($nombreTecla)) {
                                $txtProbadas.Text = "Teclas probadas: $($teclasProbadas.Count) / $totalTeclas"
                            }
                        }
                        $txtUltimaTecla.Text = "Ultima tecla detectada: $nombreTecla"
                    } else {
                        $teclasActivas.Remove($nombreTecla) | Out-Null
                        $ultimoLevantadaMs[$nombreTecla] = $tiempo
                        Iluminar-Tecla -MapaTeclas $mapaTeclas -NombreTecla $nombreTecla -Color $colorPresionado
                    }
                }
                if ($txtCodigoEspecial) {
                    $estadoTxt = if ($esBajada) { "pulsada" } else { "liberada" }
                    $txtCodigoEspecial.Text = "Ultimo codigo detectado: VK=0x$('{0:X2}' -f $vk) ($vk)  ScanCode=0x$('{0:X2}' -f $sc) ($sc)  [$estadoTxt]"
                }
            }
        }.GetNewClosure())
        $timerEspecial.Start()

        # PreviewKeyDown/PreviewKeyUp quedan como respaldo (por si la ventana
        # si llega a tener el foco de Windows): si llegan a disparar, solo
        # refuerzan la misma iluminacion que ya hace el gancho global, que es
        # la fuente principal y fiable.
        $winTec.Focusable = $true
        $winTec.Add_Loaded({
            $winTec.Activate() | Out-Null
            [System.Windows.Input.Keyboard]::Focus($winTec) | Out-Null
        }.GetNewClosure())
        $winTec.Add_PreviewKeyDown({
            param($s, $e)
            $nombreTecla = $e.Key.ToString()
            if ($e.IsRepeat) {
                Iluminar-Tecla -MapaTeclas $mapaTeclas -NombreTecla $nombreTecla -Color $colorMantenida
            } else {
                Iluminar-Tecla -MapaTeclas $mapaTeclas -NombreTecla $nombreTecla -Color $colorPresionado
            }
            $e.Handled = $true
        }.GetNewClosure())
        $winTec.Add_PreviewKeyUp({
            param($s, $e)
            $nombreTecla = $e.Key.ToString()
            Iluminar-Tecla -MapaTeclas $mapaTeclas -NombreTecla $nombreTecla -Color $colorPresionado
            $e.Handled = $true
        }.GetNewClosure())

        $winTec.FindName("BtnReporteRebotes").Add_Click({
            # Los botones tambien corren dentro de un .GetNewClosure(), asi
            # que solo pueden llamar funciones Global: -- Show-Aviso ya lo es.
            if ($registroRebotes.Count -eq 0) {
                Show-Aviso -Mensaje "No se detecto ninguna tecla con posible rebote de hardware en esta sesion de prueba." -Titulo "Reporte de teclado - The Dragon Tool"
            } else {
                $lineas = foreach ($nombre in ($registroRebotes.Keys | Sort-Object)) {
                    $info = $registroRebotes[$nombre]
                    "- $nombre : $($info.Conteo) veces (menor intervalo detectado: $($info.MenorIntervalo) ms)"
                }
                $texto = "Se detectaron posibles fallas de hardware (rebote) en estas teclas:`n`n" + ($lineas -join "`n") + "`n`nUn 'rebote' significa que, al presionar la tecla UNA sola vez, el interruptor mando la señal de pulsacion mas de una vez en menos de $umbralReboteMs ms -- algo que una persona no puede hacer fisicamente a proposito. Normalmente indica un interruptor de tecla desgastado o con suciedad debajo, y suele empeorar con el tiempo."
                Show-Aviso -Mensaje $texto -Titulo "Reporte de teclado - The Dragon Tool"
            }
        }.GetNewClosure())
        $winTec.FindName("BtnReiniciarTeclado").Add_Click({
            foreach ($k in $mapaTeclas.Keys) {
                $fondoOriginal = Nuevo-FondoTecla -ColorBase $mapaColorBase[$k]
                foreach ($b in $mapaTeclas[$k]) { $b.Background = $fondoOriginal }
            }
            $teclasActivas.Clear()
            $teclasProbadas.Clear()
            $ultimoLevantadaMs.Clear()
            $registroRebotes.Clear()
            $txtProbadas.Text = "Teclas probadas: 0 / $totalTeclas"
            $txtUltimaTecla.Text = "Ultima tecla: (ninguna)"
            $txtRebotes.Text = ""
        }.GetNewClosure())
        $winTec.FindName("BtnCerrarTeclado").Add_Click({ $winTec.Close() })
        $winTec.Add_Closed({
            $timerEspecial.Stop()
            [DragonToolTecladoHook]::Desinstalar()
        }.GetNewClosure())

        $winTec.ShowDialog() | Out-Null
        if ($registroRebotes.Count -gt 0) {
            $resumen = ($registroRebotes.Keys | Sort-Object | ForEach-Object { "$_ (x$($registroRebotes[$_].Conteo))" }) -join ", "
            Write-DiagLog "Prueba de teclado finalizada. Posibles fallas de hardware (rebote) detectadas en: $resumen"
        } else {
            Write-DiagLog "Prueba de teclado finalizada. No se detectaron teclas con posible rebote de hardware."
        }
    } catch {
        try { [DragonToolTecladoHook]::Desinstalar() } catch {}
        Write-DiagLog "No se pudo abrir la prueba de teclado: $($_.Exception.Message)"
    }
}

# --- Microfono: medidor de nivel en tiempo real (captura directa, sin abrir Windows) ---

$Script:TipoMicTestListo = $false
function Ensure-TipoMicTest {
    if ($Script:TipoMicTestListo) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;

public class DragonToolMicTest {
    [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr hWaveIn, int uDeviceID, ref WAVEFORMATEX lpFormat, IntPtr dwCallback, IntPtr dwInstance, int dwFlags);
    [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr hWaveIn, ref WAVEHDR lpWaveInHdr, int uSize);
    [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr hWaveIn, ref WAVEHDR lpWaveInHdr, int uSize);
    [DllImport("winmm.dll")] static extern int waveInStart(IntPtr hWaveIn);
    [DllImport("winmm.dll")] static extern int waveInStop(IntPtr hWaveIn);
    [DllImport("winmm.dll")] static extern int waveInClose(IntPtr hWaveIn);
    [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr hWaveIn, ref WAVEHDR lpWaveInHdr, int uSize);

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEFORMATEX {
        public ushort wFormatTag; public ushort nChannels; public uint nSamplesPerSec;
        public uint nAvgBytesPerSec; public ushort nBlockAlign; public ushort wBitsPerSample; public ushort cbSize;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEHDR {
        public IntPtr lpData; public uint dwBufferLength; public uint dwBytesRecorded;
        public IntPtr dwUser; public uint dwFlags; public uint dwLoops; public IntPtr lpNext; public IntPtr reserved;
    }

    IntPtr hWaveIn = IntPtr.Zero;
    WAVEHDR hdr;
    IntPtr bufferPtr = IntPtr.Zero;
    int bufferSize = 8192;
    bool activo = false;

    public bool Iniciar() {
        WAVEFORMATEX fmt = new WAVEFORMATEX();
        fmt.wFormatTag = 1; fmt.nChannels = 1; fmt.nSamplesPerSec = 11025; fmt.wBitsPerSample = 16;
        fmt.nBlockAlign = (ushort)(fmt.nChannels * fmt.wBitsPerSample / 8);
        fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;
        fmt.cbSize = 0;

        int result = waveInOpen(out hWaveIn, -1, ref fmt, IntPtr.Zero, IntPtr.Zero, 0);
        if (result != 0) return false;

        bufferPtr = Marshal.AllocHGlobal(bufferSize);
        hdr = new WAVEHDR();
        hdr.lpData = bufferPtr;
        hdr.dwBufferLength = (uint)bufferSize;
        waveInPrepareHeader(hWaveIn, ref hdr, Marshal.SizeOf(hdr));
        waveInAddBuffer(hWaveIn, ref hdr, Marshal.SizeOf(hdr));
        waveInStart(hWaveIn);
        activo = true;
        return true;
    }

    public int LeerNivelPico() {
        if (!activo) return 0;
        int peak = 0;
        if ((hdr.dwFlags & 1) != 0) {
            int muestras = (int)hdr.dwBytesRecorded / 2;
            for (int i = 0; i < muestras; i++) {
                short muestra = Marshal.ReadInt16(bufferPtr, i * 2);
                int abs = Math.Abs((int)muestra);
                if (abs > peak) peak = abs;
            }
            waveInUnprepareHeader(hWaveIn, ref hdr, Marshal.SizeOf(hdr));
            hdr.dwBufferLength = (uint)bufferSize; hdr.dwBytesRecorded = 0; hdr.dwFlags = 0;
            waveInPrepareHeader(hWaveIn, ref hdr, Marshal.SizeOf(hdr));
            waveInAddBuffer(hWaveIn, ref hdr, Marshal.SizeOf(hdr));
        }
        return peak;
    }

    public void Detener() {
        if (!activo) return;
        activo = false;
        try {
            waveInStop(hWaveIn);
            waveInUnprepareHeader(hWaveIn, ref hdr, Marshal.SizeOf(hdr));
            waveInClose(hWaveIn);
        } catch {}
        if (bufferPtr != IntPtr.Zero) { Marshal.FreeHGlobal(bufferPtr); bufferPtr = IntPtr.Zero; }
    }
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoMicTestListo = $true
}

function Show-PruebaMicrofono {
    Write-DiagLog "=== MICROFONO (medidor de nivel en vivo, captura directa) ==="
    try {
        Ensure-TipoMicTest
    } catch {
        Write-DiagLog "No se pudo preparar la prueba de microfono: $($_.Exception.Message)"
        return
    }
    try {
        [xml]$xamlMic = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Prueba de microfono - The Dragon Tool" Height="310" Width="480" WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <StackPanel Margin="20">
    <Button x:Name="BtnVolverVentana" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock Text="Habla cerca del microfono: la barra debe moverse en tiempo real si funciona." Foreground="White" TextWrapping="Wrap" Margin="0,0,0,14"/>
    <ProgressBar x:Name="BarraNivelMic" Minimum="0" Maximum="100" Height="30" Margin="0,0,0,10"/>
    <TextBlock x:Name="TxtNivelMic" Text="Nivel: 0%" Foreground="#66AEFF" FontWeight="Bold"/>
    <Button x:Name="BtnCerrarMic" Content="Cerrar" Height="38" Margin="0,20,0,0"/>
  </StackPanel>
</Window>
"@
        $readerMic = New-Object System.Xml.XmlNodeReader $xamlMic
        $winMic = [Windows.Markup.XamlReader]::Load($readerMic)
        Iniciar-EfectosNeon -Ventana $winMic
        $barra = $winMic.FindName("BarraNivelMic")
        $txtNivel = $winMic.FindName("TxtNivelMic")

        $mic = New-Object DragonToolMicTest
        if (-not $mic.Iniciar()) {
            Write-DiagLog "No se pudo iniciar la captura de microfono (puede estar en uso por otra app o no haber ninguno conectado)."
            return
        }

        $timerMic = New-Object System.Windows.Threading.DispatcherTimer
        $timerMic.Interval = [TimeSpan]::FromMilliseconds(120)
        $timerMic.Add_Tick({
            $nivel = $mic.LeerNivelPico()
            $pct = [math]::Min(100, [math]::Round(($nivel / 32767) * 300))
            $barra.Value = $pct
            $txtNivel.Text = "Nivel: $pct%"
        }.GetNewClosure())
        $timerMic.Start()

        $winMic.Add_Closed({ $timerMic.Stop(); $mic.Detener() }.GetNewClosure())
        $winMic.FindName("BtnCerrarMic").Add_Click({ $winMic.Close() })

        $winMic.ShowDialog() | Out-Null
        Write-DiagLog "Prueba de microfono finalizada."
    } catch {
        Write-DiagLog "No se pudo completar la prueba de microfono: $($_.Exception.Message)"
    }
}

# --- Audio: generador de tonos propio (sin abrir el panel de sonido de Windows) ---

function New-TonoWav {
    param([double]$Frecuencia = 440, [double]$DuracionSegundos = 1.5, [string]$Canal = "Ambos")
    $sampleRate = 44100
    $numSamples = [int]($sampleRate * $DuracionSegundos)
    $dataSize = $numSamples * 2 * 2

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([char[]]"RIFF"); $bw.Write([int32](36 + $dataSize)); $bw.Write([char[]]"WAVE")
    $bw.Write([char[]]"fmt "); $bw.Write([int32]16); $bw.Write([int16]1); $bw.Write([int16]2)
    $bw.Write([int32]$sampleRate); $bw.Write([int32]($sampleRate * 4)); $bw.Write([int16]4); $bw.Write([int16]16)
    $bw.Write([char[]]"data"); $bw.Write([int32]$dataSize)

    for ($i = 0; $i -lt $numSamples; $i++) {
        $t = $i / $sampleRate
        $valor = [math]::Sin(2 * [math]::PI * $Frecuencia * $t) * 0.5
        $muestra = [int16]($valor * [int16]::MaxValue)
        $izq = [int16]0; $der = [int16]0
        switch ($Canal) {
            'Izquierdo' { $izq = $muestra }
            'Derecho'   { $der = $muestra }
            default     { $izq = $muestra; $der = $muestra }
        }
        $bw.Write($izq); $bw.Write($der)
    }
    $bw.Flush()
    $ms.Position = 0
    return $ms
}

function Accion-ProbarAudioCanal {
    param([string]$Canal)
    Write-DiagLog "=== AUDIO / ALTAVOCES ($Canal) ==="
    try {
        $ms = New-TonoWav -Frecuencia 440 -DuracionSegundos 1.5 -Canal $Canal
        $player = New-Object System.Media.SoundPlayer
        $player.Stream = $ms
        $player.PlaySync()
        $ms.Dispose()
        Write-DiagLog "Tono de prueba reproducido en: $Canal. ¿Se escucho correctamente de ese lado?"
    } catch {
        Write-DiagLog "No se pudo reproducir el tono de prueba: $($_.Exception.Message)"
    }
}

function Show-PruebaPantalla {
    Write-DiagLog "=== PANTALLA ==="
    Write-DiagLog "Se abrira una ventana a pantalla completa con colores solidos. Revisa manchas o pixeles muertos. Clic para cambiar de color, Esc para salir."
    try {
        [xml]$xamlPant = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" WindowState="Maximized" Background="White" Topmost="True" ShowInTaskbar="False">
  <TextBlock Text="Clic = cambiar de color      Esc = salir" Foreground="Gray" FontSize="16"
             HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,30"/>
</Window>
"@
        $readerP = New-Object System.Xml.XmlNodeReader $xamlPant
        $winP = [Windows.Markup.XamlReader]::Load($readerP)
        $colores = @('White', 'Red', 'Lime', 'Blue', 'Black', 'Gray')
        $Script:_idxColorPantalla = 0
        $winP.Add_MouseLeftButtonDown({
            $Script:_idxColorPantalla = ($Script:_idxColorPantalla + 1) % $colores.Count
            $winP.Background = [System.Windows.Media.Brushes]::($colores[$Script:_idxColorPantalla])
        }.GetNewClosure())
        $winP.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq 'Escape') { $winP.Close() }
        })
        $winP.ShowDialog() | Out-Null
        Write-DiagLog "Prueba de pantalla finalizada."
    } catch {
        Write-DiagLog "No se pudo abrir la prueba de pantalla: $($_.Exception.Message)"
    }
}

function Accion-VerDetallesPantalla {
    Write-DiagLog "=== PANTALLA: DETALLES ==="
    try {
        $monitores = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
        foreach ($m in $monitores) {
            $nombre = -join ($m.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            if ($nombre) { Write-DiagLog " - Monitor: $nombre" }
        }
        $videoCtrl = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        foreach ($v in $videoCtrl) {
            if ($v.CurrentHorizontalResolution) {
                Write-DiagLog " - Resolucion actual: $($v.CurrentHorizontalResolution) x $($v.CurrentVerticalResolution) @ $($v.CurrentRefreshRate) Hz"
            }
        }
        if (-not $monitores -and -not $videoCtrl) { Write-DiagLog "No se pudo obtener el detalle de pantalla." }
    } catch {
        Write-DiagLog "No se pudo obtener el detalle de pantalla."
    }
}

# --- RAM: prueba propia de patrones (sin reiniciar, sin abrir Windows) ---

$Script:TipoMemTestListo = $false
function Ensure-TipoMemTest {
    if ($Script:TipoMemTestListo) { return }
    $codigo = @"
using System;

public static class DragonToolMemTest {
    public static void Fill(byte[] buffer, byte pattern) {
        for (int i = 0; i < buffer.Length; i++) buffer[i] = pattern;
    }
    public static long CountMismatches(byte[] buffer, byte pattern) {
        long count = 0;
        for (int i = 0; i < buffer.Length; i++) {
            if (buffer[i] != pattern) count++;
        }
        return count;
    }
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoMemTestListo = $true
}

function Show-PruebaRAM {
    param(
        [int]$TamanoMB = 512,
        [array]$Patrones = @(0xFF, 0x00, 0xAA, 0x55, 0x01, 0xFE),
        [string]$ModoEjecucion = 'Pasadas',   # 'Pasadas' | 'Tiempo' | 'Bucle'
        [int]$Pasadas = 1,
        [int]$DuracionMinutos = 5
    )
    Write-DiagLog "=== MEMORIA RAM (prueba propia, sin reiniciar) ==="

    # Un array de bytes en .NET no puede superar Int32.MaxValue elementos
    # (2147483647). 2048 MB exactos ya superan ese limite por 1 byte, asi que
    # se limita el tamaño maximo permitido a un valor seguro.
    $maxSeguroMB = [math]::Floor([int32]::MaxValue / 1MB)
    if ($TamanoMB -gt $maxSeguroMB) {
        Write-DiagLog "El tamaño solicitado ($TamanoMB MB) supera el maximo posible para esta prueba. Se ajusta a $maxSeguroMB MB."
        $TamanoMB = $maxSeguroMB
    }

    try {
        Ensure-TipoMemTest
    } catch {
        Write-DiagLog "No se pudo preparar la prueba de RAM: $($_.Exception.Message)"
        return
    }

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $ramLibreMB = [math]::Round($os.FreePhysicalMemory / 1KB)
        if ($TamanoMB -gt ($ramLibreMB * 0.6)) {
            if (-not (Show-Confirm "Pediste probar $TamanoMB MB, pero solo hay $ramLibreMB MB de RAM libre. Esto puede ralentizar mucho el equipo o fallar. ¿Continuar de todas formas?")) {
                Write-DiagLog "Prueba de RAM cancelada (memoria libre insuficiente para el tamaño solicitado)."
                return
            }
        }
    } catch {}

    $descripcionModo = switch ($ModoEjecucion) {
        'Tiempo' { "durante $DuracionMinutos minuto(s)" }
        'Bucle'  { "en bucle continuo hasta que la detengas manualmente" }
        default  { "con $Pasadas pasada(s)" }
    }
    if (-not (Show-Confirm "Se probaran $TamanoMB MB con $($Patrones.Count) patron(es) $descripcionModo, dentro de Windows (no requiere reiniciar). ¿Continuar?")) {
        Write-DiagLog "Prueba de RAM cancelada por el usuario."
        return
    }

    $permitirDetener = ($ModoEjecucion -ne 'Pasadas') -or ($Pasadas -gt 1)
    $prog = New-VentanaProgreso -Titulo "Probando memoria RAM" -PermitirDetener:$permitirDetener
    try {
        Update-VentanaProgreso -Ventana $prog -Porcentaje 2 -Estado "Reservando $TamanoMB MB de memoria para la prueba..." -LogLinea "Reservando bloque de prueba de $TamanoMB MB."
        $buffer = New-Object byte[] ($TamanoMB * 1MB)

        $erroresTotal = 0
        $pasadasCompletadas = 0
        $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
        $detenido = $false

        while (-not $detenido) {
            $pasadasCompletadas++
            foreach ($patron in $Patrones) {
                if ($prog.Tag -eq $true) { $detenido = $true; break }

                $patronTexto = "0x{0:X2}" -f $patron
                $idxPatron = [Array]::IndexOf($Patrones, $patron) + 1

                switch ($ModoEjecucion) {
                    'Tiempo' {
                        $pct = [math]::Min(98, [math]::Round(($cronometro.Elapsed.TotalMinutes / [math]::Max($DuracionMinutos,0.01)) * 100))
                        $tiempoTexto = "{0:N1}" -f $cronometro.Elapsed.TotalMinutes
                        $etiqueta = "Pasada $pasadasCompletadas, patron $patronTexto ($tiempoTexto / $DuracionMinutos min)"
                    }
                    'Bucle' {
                        $pct = [math]::Round(($idxPatron / $Patrones.Count) * 100)
                        $etiqueta = "Pasada $pasadasCompletadas (bucle continuo), patron $patronTexto"
                    }
                    default {
                        $totalPasos = $Patrones.Count * $Pasadas
                        $pasoActual = (($pasadasCompletadas - 1) * $Patrones.Count) + $idxPatron
                        $pct = [math]::Round(($pasoActual / $totalPasos) * 100)
                        $etiqueta = "Pasada $pasadasCompletadas de $Pasadas, patron $patronTexto"
                    }
                }
                Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "$etiqueta..." -LogLinea "$etiqueta."

                [DragonToolMemTest]::Fill($buffer, [byte]$patron)
                $errores = [DragonToolMemTest]::CountMismatches($buffer, [byte]$patron)
                $erroresTotal += $errores
                if ($errores -gt 0) {
                    Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "¡$errores error(es) detectados con el patron $patronTexto!"
                }
            }

            if ($detenido) { break }
            switch ($ModoEjecucion) {
                'Tiempo' { if ($cronometro.Elapsed.TotalMinutes -ge $DuracionMinutos) { $detenido = $true } }
                'Bucle'  { }
                default  { if ($pasadasCompletadas -ge $Pasadas) { $detenido = $true } }
            }
        }
        $cronometro.Stop()

        Update-VentanaProgreso -Ventana $prog -Porcentaje 100 -Estado "Finalizando..."
        $buffer = $null
        [System.GC]::Collect()

        $resumen = "$TamanoMB MB, $pasadasCompletadas pasada(s), $("{0:N1}" -f $cronometro.Elapsed.TotalMinutes) minuto(s)"
        if ($erroresTotal -eq 0) {
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "Sin errores detectados."
            Write-DiagLog "Prueba de RAM completada sin errores: $resumen."
        } else {
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "$erroresTotal error(es) detectados."
            Write-DiagLog "ATENCION: se detectaron $erroresTotal error(es) de memoria tras $resumen. Se recomienda una prueba mas exhaustiva (con reinicio) para confirmar, por ejemplo desde Windows."
        }
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error durante la prueba."
        Write-DiagLog "No se pudo completar la prueba de RAM: $($_.Exception.Message)"
    }
}

function Show-SeleccionPruebaRAM {
    [xml]$xamlSelRam = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Elegir tipo de prueba de RAM - The Dragon Tool" Height="640" Width="500"
        WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24">
    <Button x:Name="BtnVolverVentana" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock Text="Tamaño de la prueba:" Foreground="#66AEFF" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>

    <RadioButton x:Name="RbRamRapida" GroupName="TipoRAM" Foreground="White" IsChecked="True" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Text="🟢 Rapida" FontWeight="Bold"/>
        <TextBlock Text="128 MB, 2 patrones. Lista en segundos, buena para un vistazo rapido." FontSize="11" Opacity="0.85" TextWrapping="Wrap"/>
      </StackPanel>
    </RadioButton>

    <RadioButton x:Name="RbRamEstandar" GroupName="TipoRAM" Foreground="White" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Text="🟡 Estandar (recomendada)" FontWeight="Bold"/>
        <TextBlock Text="512 MB, 6 patrones. Buen equilibrio entre rapidez y cobertura." FontSize="11" Opacity="0.85" TextWrapping="Wrap"/>
      </StackPanel>
    </RadioButton>

    <RadioButton x:Name="RbRamExhaustiva" GroupName="TipoRAM" Foreground="White" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Text="🔴 Exhaustiva" FontWeight="Bold"/>
        <TextBlock Text="1900 MB, 10 patrones. Mas lenta y usa mas RAM libre." FontSize="11" Opacity="0.85" TextWrapping="Wrap"/>
      </StackPanel>
    </RadioButton>

    <RadioButton x:Name="RbRamPersonalizada" GroupName="TipoRAM" Foreground="White" Margin="0,0,0,6">
      <TextBlock Text="⚙️ Personalizada" FontWeight="Bold"/>
    </RadioButton>
    <StackPanel x:Name="PanelRamPersonalizada" Visibility="Collapsed" Margin="24,4,0,10">
      <DockPanel Margin="0,4,0,4">
        <TextBlock Text="Tamaño (MB):" Foreground="White" Width="100" VerticalAlignment="Center"/>
        <TextBox x:Name="TxtRamTamano" Text="1024"/>
      </DockPanel>
    </StackPanel>

    <Separator Margin="0,6,0,14" Opacity="0.2"/>

    <TextBlock Text="Modo de ejecucion:" Foreground="#66AEFF" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>

    <RadioButton x:Name="RbModoPasadas" GroupName="ModoRAM" Foreground="White" IsChecked="True" Margin="0,0,0,6">
      <TextBlock Text="Numero de pasadas" FontWeight="Bold"/>
    </RadioButton>
    <StackPanel x:Name="PanelModoPasadas" Margin="24,0,0,10">
      <DockPanel Margin="0,4,0,4">
        <TextBlock Text="Pasadas:" Foreground="White" Width="100" VerticalAlignment="Center"/>
        <TextBox x:Name="TxtRamPasadas" Text="1"/>
      </DockPanel>
    </StackPanel>

    <RadioButton x:Name="RbModoTiempo" GroupName="ModoRAM" Foreground="White" Margin="0,0,0,6">
      <TextBlock Text="Por tiempo de duracion" FontWeight="Bold"/>
    </RadioButton>
    <StackPanel x:Name="PanelModoTiempo" Visibility="Collapsed" Margin="24,0,0,10">
      <DockPanel Margin="0,4,0,4">
        <TextBlock Text="Minutos:" Foreground="White" Width="100" VerticalAlignment="Center"/>
        <TextBox x:Name="TxtRamMinutos" Text="5"/>
      </DockPanel>
    </StackPanel>

    <RadioButton x:Name="RbModoBucle" GroupName="ModoRAM" Foreground="White" Margin="0,0,0,6">
      <StackPanel>
        <TextBlock Text="En bucle continuo" FontWeight="Bold"/>
        <TextBlock Text="Se repite sin parar hasta que pulses 'Detener' en la ventana de progreso." FontSize="11" Opacity="0.85" TextWrapping="Wrap"/>
      </StackPanel>
    </RadioButton>

    <Button x:Name="BtnIniciarPruebaRAM" Content="▶️ Iniciar prueba" Height="42" Margin="0,16,0,0" BorderBrush="#2F7CF6"/>
  </StackPanel>
  </ScrollViewer>
</Window>
"@
    $readerSelRam = New-Object System.Xml.XmlNodeReader $xamlSelRam
    $winSelRam = [Windows.Markup.XamlReader]::Load($readerSelRam)
    Iniciar-EfectosNeon -Ventana $winSelRam

    $winSelRam.FindName("RbRamPersonalizada").Add_Checked({
        $winSelRam.FindName("PanelRamPersonalizada").Visibility = 'Visible'
    })
    foreach ($otro in @("RbRamRapida", "RbRamEstandar", "RbRamExhaustiva")) {
        $winSelRam.FindName($otro).Add_Checked({
            $winSelRam.FindName("PanelRamPersonalizada").Visibility = 'Collapsed'
        }.GetNewClosure())
    }

    $winSelRam.FindName("RbModoPasadas").Add_Checked({
        $winSelRam.FindName("PanelModoPasadas").Visibility = 'Visible'
        $winSelRam.FindName("PanelModoTiempo").Visibility = 'Collapsed'
    })
    $winSelRam.FindName("RbModoTiempo").Add_Checked({
        $winSelRam.FindName("PanelModoPasadas").Visibility = 'Collapsed'
        $winSelRam.FindName("PanelModoTiempo").Visibility = 'Visible'
    })
    $winSelRam.FindName("RbModoBucle").Add_Checked({
        $winSelRam.FindName("PanelModoPasadas").Visibility = 'Collapsed'
        $winSelRam.FindName("PanelModoTiempo").Visibility = 'Collapsed'
    })

    $winSelRam.FindName("BtnIniciarPruebaRAM").Add_Click({
        if ($winSelRam.FindName("RbRamRapida").IsChecked) {
            $tamanoSel = 128; $patronesSel = @(0xFF, 0x00)
        } elseif ($winSelRam.FindName("RbRamEstandar").IsChecked) {
            $tamanoSel = 512; $patronesSel = @(0xFF, 0x00, 0xAA, 0x55, 0x01, 0xFE)
        } elseif ($winSelRam.FindName("RbRamExhaustiva").IsChecked) {
            $tamanoSel = 1900; $patronesSel = @(0xFF, 0x00, 0xAA, 0x55, 0x01, 0xFE, 0x33, 0xCC, 0x0F, 0xF0)
        } else {
            $tamanoSel = 1024
            [int]::TryParse($winSelRam.FindName("TxtRamTamano").Text, [ref]$tamanoSel) | Out-Null
            if ($tamanoSel -lt 16) { $tamanoSel = 16 }
            $patronesSel = @(0xFF, 0x00, 0xAA, 0x55, 0x01, 0xFE)
        }

        if ($winSelRam.FindName("RbModoTiempo").IsChecked) {
            $minutosSel = 5
            [int]::TryParse($winSelRam.FindName("TxtRamMinutos").Text, [ref]$minutosSel) | Out-Null
            if ($minutosSel -lt 1) { $minutosSel = 1 }
            $winSelRam.Close()
            Show-PruebaRAM -TamanoMB $tamanoSel -Patrones $patronesSel -ModoEjecucion 'Tiempo' -DuracionMinutos $minutosSel
        } elseif ($winSelRam.FindName("RbModoBucle").IsChecked) {
            $winSelRam.Close()
            Show-PruebaRAM -TamanoMB $tamanoSel -Patrones $patronesSel -ModoEjecucion 'Bucle'
        } else {
            $pasadasSel = 1
            [int]::TryParse($winSelRam.FindName("TxtRamPasadas").Text, [ref]$pasadasSel) | Out-Null
            if ($pasadasSel -lt 1) { $pasadasSel = 1 }
            $winSelRam.Close()
            Show-PruebaRAM -TamanoMB $tamanoSel -Patrones $patronesSel -ModoEjecucion 'Pasadas' -Pasadas $pasadasSel
        }
    })

    $winSelRam.ShowDialog() | Out-Null
}

function Accion-ProbarAlmacenamiento {
    Write-DiagLog "=== ALMACENAMIENTO ==="
    try {
        $discos = Get-PhysicalDisk -ErrorAction Stop
        foreach ($d in $discos) {
            Write-DiagLog " - $($d.FriendlyName) | Salud: $($d.HealthStatus) | Estado: $($d.OperationalStatus)"
        }
    } catch {
        Write-DiagLog "No se pudo usar Get-PhysicalDisk en este equipo."
    }
    try {
        $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        foreach ($s in $smart) {
            $estado = if ($s.PredictFailure) { "FALLO INMINENTE DETECTADO (S.M.A.R.T.)" } else { "Sin fallos detectados (S.M.A.R.T. OK)" }
            Write-DiagLog " - $($s.InstanceName): $estado"
        }
    } catch {
        Write-DiagLog "No se pudo leer el estado S.M.A.R.T. detallado en este equipo."
    }
}

function Accion-ProbarVelocidadDisco {
    Write-DiagLog "=== VELOCIDAD DE DISCO (lectura/escritura, C:) ==="
    try {
        $carpetaPrueba = Join-Path $env:TEMP "DragonToolDiskTest"
        if (-not (Test-Path $carpetaPrueba)) { New-Item -Path $carpetaPrueba -ItemType Directory -Force | Out-Null }
        $archivoPrueba = Join-Path $carpetaPrueba "prueba.tmp"
        $tamanoMB = 200
        $datos = New-Object byte[] ($tamanoMB * 1MB)
        (New-Object Random).NextBytes($datos)

        $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($archivoPrueba, $datos)
        $cronometro.Stop()
        $velocidadEscritura = [math]::Round($tamanoMB / $cronometro.Elapsed.TotalSeconds, 1)

        $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::ReadAllBytes($archivoPrueba) | Out-Null
        $cronometro.Stop()
        $velocidadLectura = [math]::Round($tamanoMB / $cronometro.Elapsed.TotalSeconds, 1)

        Remove-Item $archivoPrueba -Force -ErrorAction SilentlyContinue
        $datos = $null
        Write-DiagLog "Escritura: $velocidadEscritura MB/s | Lectura: $velocidadLectura MB/s (prueba de $tamanoMB MB en $carpetaPrueba)"
    } catch {
        Write-DiagLog "No se pudo medir la velocidad de disco: $($_.Exception.Message)"
    }
}

function Accion-ProbarVentiladores {
    Write-DiagLog "=== VENTILADORES ==="
    try {
        $fans = Get-CimInstance Win32_Fan -ErrorAction Stop
        if ($fans -and $fans.Count -gt 0) {
            foreach ($f in $fans) { Write-DiagLog " - $($f.Name) | Estado: $($f.Status)" }
        } else {
            Write-DiagLog "Windows no expone datos de ventiladores en este equipo. Es una limitacion muy comun: la mayoria de fabricantes solo la muestran en su propia app (MSI Center, Armoury Crate, HWiNFO, etc.), no es un error de este programa."
        }
    } catch {
        Write-DiagLog "Windows no expone datos de ventiladores en este equipo (limitacion comun de hardware/BIOS)."
    }
}

function Accion-ProbarGraficaDiag {
    Write-DiagLog "=== TARJETA GRAFICA ==="
    $gpus = Get-InfoGPU
    if ($gpus -and $gpus.Count -gt 0) {
        foreach ($g in $gpus) { Write-DiagLog " - $($g.Nombre) [$($g.Fabricante)] | Driver: $($g.DriverVersion)" }
    } else {
        Write-DiagLog "No se detecto ninguna tarjeta de video."
    }
}

function Accion-ProbarBateria {
    Write-DiagLog "=== BATERIA ==="
    try {
        $bateria = Get-CimInstance Win32_Battery -ErrorAction Stop
        if (-not $bateria) {
            Write-DiagLog "No se detecto ninguna bateria (equipo de escritorio, o bateria no reconocida)."
            return
        }
        foreach ($b in $bateria) {
            Write-DiagLog " - $($b.Name) | Estado: $($b.Status) | Carga estimada: $($b.EstimatedChargeRemaining)%"
        }
        try {
            $carpetaTemp = Join-Path $env:TEMP "DragonToolBattery"
            if (-not (Test-Path $carpetaTemp)) { New-Item -Path $carpetaTemp -ItemType Directory -Force | Out-Null }
            $archivoXml = Join-Path $carpetaTemp "battery-report.xml"
            powercfg /batteryreport /xml /output $archivoXml *> $null
            if (Test-Path $archivoXml) {
                $contenido = Get-Content $archivoXml -Raw
                $disenoMatch = [regex]::Match($contenido, 'DesignCapacity="(\d+)"')
                $actualMatch = [regex]::Match($contenido, 'FullChargeCapacity="(\d+)"')
                if ($disenoMatch.Success -and $actualMatch.Success) {
                    $diseno = [double]$disenoMatch.Groups[1].Value
                    $actual = [double]$actualMatch.Groups[1].Value
                    if ($diseno -gt 0) {
                        $desgaste = [math]::Round((1 - ($actual / $diseno)) * 100, 1)
                        Write-DiagLog "Capacidad de diseño: $diseno mWh | Capacidad maxima actual: $actual mWh | Desgaste: $desgaste%"
                    }
                }
                Remove-Item $archivoXml -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-DiagLog "No se pudo generar el reporte detallado de desgaste de bateria (no critico)."
        }
    } catch {
        Write-DiagLog "No se detecto ninguna bateria (equipo de escritorio, o bateria no reconocida)."
    }
}

function Accion-ProbarRed {
    Write-DiagLog "=== RED / CONECTIVIDAD ==="
    try {
        $resultado = Test-Connection -ComputerName "8.8.8.8" -Count 4 -ErrorAction Stop
        $latencias = $resultado | ForEach-Object { $_.ResponseTime }
        $promedio = [math]::Round(($latencias | Measure-Object -Average).Average, 0)
        $minimo = ($latencias | Measure-Object -Minimum).Minimum
        $maximo = ($latencias | Measure-Object -Maximum).Maximum
        Write-DiagLog "Conectividad a Internet: OK | Latencia promedio: $promedio ms (min $minimo ms, max $maximo ms)"
    } catch {
        Write-DiagLog "Sin conexion a Internet detectada (no respondio 8.8.8.8)."
        return
    }
    try {
        $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
        Resolve-DnsName -Name "www.google.com" -ErrorAction Stop | Out-Null
        $cronometro.Stop()
        Write-DiagLog "Resolucion DNS: OK ($($cronometro.ElapsedMilliseconds) ms)"
    } catch {
        Write-DiagLog "No se pudo resolver DNS (posible problema con el servidor DNS configurado)."
    }
    try {
        $conexionHttps = Test-NetConnection -ComputerName "www.google.com" -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
        if ($conexionHttps.TcpTestSucceeded) { Write-DiagLog "Conexion HTTPS (puerto 443) de salida: OK" }
        else { Write-DiagLog "No se pudo establecer conexion HTTPS de salida (revisa el firewall)." }
    } catch {
        Write-DiagLog "No se pudo probar la conexion HTTPS de salida."
    }
}

function Accion-ProbarTemperaturaCPU {
    Write-DiagLog "=== TEMPERATURA DEL PROCESADOR ==="
    try {
        $temp = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction Stop
        if ($temp) {
            foreach ($t in $temp) {
                $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
                Write-DiagLog " - Zona termica: $celsius °C"
            }
        } else {
            Write-DiagLog "Windows no expone la temperatura en este equipo. Es una limitacion comun: muchos fabricantes solo la muestran en su propia app (HWiNFO, software de la placa madre, etc.), no es un error de este programa."
        }
    } catch {
        Write-DiagLog "Windows no expone la temperatura del procesador en este equipo (limitacion comun de hardware/BIOS, no es un error de este programa)."
    }
}

function Accion-ProbarTiempoArranque {
    Write-DiagLog "=== TIEMPO DE ARRANQUE ==="
    try {
        $evento = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
        $xmlEvento = [xml]$evento.ToXml()
        $tiempoMs = ($xmlEvento.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text'
        if ($tiempoMs) {
            $segundos = [math]::Round([double]$tiempoMs / 1000, 1)
            Write-DiagLog "El ultimo arranque de Windows tardo: $segundos segundos (registrado: $($evento.TimeCreated))"
        } else {
            Write-DiagLog "No se pudo leer la duracion del ultimo arranque."
        }
    } catch {
        Write-DiagLog "No se pudo obtener el tiempo de arranque (el registro de eventos puede no tener esta informacion disponible en este equipo)."
    }
}

function Accion-ProbarBluetooth {
    Write-DiagLog "=== BLUETOOTH ==="
    try {
        $bt = Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction Stop
        if ($bt) {
            foreach ($b in $bt) { Write-DiagLog " - $($b.FriendlyName) | Estado: $($b.Status)" }
        } else {
            Write-DiagLog "No se detecto ningun adaptador Bluetooth en este equipo."
        }
    } catch {
        Write-DiagLog "No se detecto ningun adaptador Bluetooth en este equipo."
    }
}

function Accion-ProbarPuertosUSB {
    Write-DiagLog "=== DISPOSITIVOS USB CONECTADOS ==="
    try {
        $dispositivosUsb = Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.InstanceId -like 'USB\*' }
        if ($dispositivosUsb) {
            foreach ($d in $dispositivosUsb) { Write-DiagLog " - $($d.FriendlyName) | Estado: $($d.Status)" }
        } else {
            Write-DiagLog "No se detectaron dispositivos USB conectados actualmente."
        }
    } catch {
        Write-DiagLog "No se pudo obtener la lista de dispositivos USB."
    }
}

function Show-PruebaMouse {
    Write-DiagLog "=== MOUSE / TOUCHPAD (prueba interactiva) ==="
    try {
        [xml]$xamlMouse = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Prueba de mouse/touchpad - The Dragon Tool" Height="520" Width="720" WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <DockPanel Margin="14">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Text="Mueve el mouse y haz clic dentro del area. Clic izquierdo = punto verde, clic derecho = punto naranja, rueda = contador." Foreground="White" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <TextBlock x:Name="TxtInfoMouse" DockPanel.Dock="Top" Text="Posicion: -- , -- | Clics izquierdos: 0 | Clics derechos: 0 | Rueda: 0" Foreground="#66AEFF" FontWeight="Bold" Margin="0,0,0,8"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnLimpiarMouse" Content="Limpiar" Width="100" Margin="0,0,8,0"/>
      <Button x:Name="BtnCerrarMouse" Content="Cerrar" Width="100"/>
    </StackPanel>
    <Border BorderBrush="#232B3D" BorderThickness="1">
      <Canvas x:Name="CanvasMouse" Background="#151B27"/>
    </Border>
  </DockPanel>
</Window>
"@
        $readerMouse = New-Object System.Xml.XmlNodeReader $xamlMouse
        $winMouse = [Windows.Markup.XamlReader]::Load($readerMouse)
        Iniciar-EfectosNeon -Ventana $winMouse
        $canvas = $winMouse.FindName("CanvasMouse")
        $txtInfo = $winMouse.FindName("TxtInfoMouse")
        $Script:_mouseClicksIzq = 0
        $Script:_mouseClicksDer = 0
        $Script:_mouseRueda = 0

        $winMouse.Add_MouseMove({
            param($s, $e)
            $pos = $e.GetPosition($canvas)
            $txtInfo.Text = "Posicion: $([math]::Round($pos.X)) , $([math]::Round($pos.Y)) | Clics izquierdos: $($Script:_mouseClicksIzq) | Clics derechos: $($Script:_mouseClicksDer) | Rueda: $($Script:_mouseRueda)"
        })
        $canvas.Add_MouseLeftButtonDown({
            param($s, $e)
            $Script:_mouseClicksIzq++
            $pos = $e.GetPosition($canvas)
            $punto = New-Object System.Windows.Shapes.Ellipse
            $punto.Width = 14; $punto.Height = 14
            $punto.Fill = [System.Windows.Media.Brushes]::LimeGreen
            [System.Windows.Controls.Canvas]::SetLeft($punto, $pos.X - 7)
            [System.Windows.Controls.Canvas]::SetTop($punto, $pos.Y - 7)
            $canvas.Children.Add($punto) | Out-Null
        })
        $canvas.Add_MouseRightButtonDown({
            param($s, $e)
            $Script:_mouseClicksDer++
            $pos = $e.GetPosition($canvas)
            $punto = New-Object System.Windows.Shapes.Ellipse
            $punto.Width = 14; $punto.Height = 14
            $punto.Fill = [System.Windows.Media.Brushes]::OrangeRed
            [System.Windows.Controls.Canvas]::SetLeft($punto, $pos.X - 7)
            [System.Windows.Controls.Canvas]::SetTop($punto, $pos.Y - 7)
            $canvas.Children.Add($punto) | Out-Null
        })
        $canvas.Add_MouseWheel({
            param($s, $e)
            $Script:_mouseRueda += $e.Delta
        })
        $winMouse.FindName("BtnLimpiarMouse").Add_Click({ $canvas.Children.Clear() })
        $winMouse.FindName("BtnCerrarMouse").Add_Click({ $winMouse.Close() })

        $winMouse.ShowDialog() | Out-Null
        Write-DiagLog "Prueba de mouse finalizada. Clics izquierdos: $($Script:_mouseClicksIzq), derechos: $($Script:_mouseClicksDer), rueda: $($Script:_mouseRueda)."
    } catch {
        Write-DiagLog "No se pudo abrir la prueba de mouse: $($_.Exception.Message)"
    }
}

# --- Camara: vista previa en vivo propia (AForge/DirectShow, sin abrir la app Camara) ---

$Script:AForgeDir = Join-Path $Script:ScriptDir "AForgeRuntime"
$Script:AForgeDisponible = $false
$Script:TipoGdiListo = $false

function Ensure-TipoGdi {
    if ($Script:TipoGdiListo) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;
public class DragonToolGdi {
    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoGdiListo = $true
}

function Ensure-AForgeAssemblies {
    $dllCore = Join-Path $Script:AForgeDir "AForge.dll"
    $dllVideo = Join-Path $Script:AForgeDir "AForge.Video.dll"
    $dllDirectShow = Join-Path $Script:AForgeDir "AForge.Video.DirectShow.dll"
    if ((Test-Path $dllCore) -and (Test-Path $dllVideo) -and (Test-Path $dllDirectShow)) { return $true }
    try {
        Write-Log "Preparando el modulo de camara. Solo ocurre la primera vez (requiere internet)..." -Tipo INFO
        if (-not (Test-Path $Script:AForgeDir)) { New-Item -Path $Script:AForgeDir -ItemType Directory -Force | Out-Null }
        foreach ($pkg in @("AForge", "AForge.Video", "AForge.Video.DirectShow")) {
            $zipPath = Join-Path $env:TEMP "$pkg.zip"
            Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/$pkg" -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
            $extractTmp = Join-Path $env:TEMP "$pkg`_extract"
            if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force
            $dllOrigen = Get-ChildItem -Path $extractTmp -Filter "$pkg.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dllOrigen) { Copy-Item $dllOrigen.FullName (Join-Path $Script:AForgeDir "$pkg.dll") -Force }
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log "Modulo de camara preparado." -Tipo OK
        return $true
    } catch {
        Write-Log "No se pudo preparar el modulo de camara: $($_.Exception.Message)" -Tipo ERROR
        return $false
    }
}

# Carga los componentes de camara (AForge) y prepara el "receptor" de fotogramas.
# CLAVE: AForge entrega cada fotograma en un hilo propio que NO es de PowerShell; un bloque
# de PowerShell no puede ejecutarse alli ("no hay un Runspace disponible en este hilo"),
# por eso antes el fotograma nunca llegaba a la pantalla. El receptor esta escrito en C#
# (guarda el ultimo fotograma de forma segura) y un temporizador de la interfaz lo lee.
$Script:ReceptorCamaraListo = $false
function Initialize-ModuloCamara {
    if (-not $Script:AForgeDisponible) {
        if (-not (Ensure-AForgeAssemblies)) { return $false }
        try {
            Add-Type -Path (Join-Path $Script:AForgeDir "AForge.dll")
            Add-Type -Path (Join-Path $Script:AForgeDir "AForge.Video.dll")
            Add-Type -Path (Join-Path $Script:AForgeDir "AForge.Video.DirectShow.dll")
            $Script:AForgeDisponible = $true
        } catch {
            Write-Log "No se pudieron cargar los componentes de camara: $($_.Exception.Message)" -Tipo ERROR
            return $false
        }
    }
    if (-not $Script:ReceptorCamaraListo) {
        try {
            $codigoReceptor = @"
using System;
using System.Drawing;
using AForge.Video;
public class DragonCamReceptor {
    private readonly object cerrojo = new object();
    private Bitmap ultimo;
    private long total;
    public string UltimoError;
    public long TotalFotogramas { get { lock (cerrojo) { return total; } } }
    public void Conectar(IVideoSource fuente) {
        fuente.NewFrame += new NewFrameEventHandler(AlLlegarFotograma);
        fuente.VideoSourceError += new VideoSourceErrorEventHandler(AlFallar);
    }
    private void AlLlegarFotograma(object remitente, NewFrameEventArgs e) {
        Bitmap copia = null;
        try { copia = (Bitmap)e.Frame.Clone(); } catch { return; }
        lock (cerrojo) {
            if (ultimo != null) { ultimo.Dispose(); }
            ultimo = copia;
            total++;
        }
    }
    private void AlFallar(object remitente, VideoSourceErrorEventArgs e) { UltimoError = e.Description; }
    public Bitmap Tomar() { lock (cerrojo) { Bitmap b = ultimo; ultimo = null; return b; } }
    public void Liberar() { lock (cerrojo) { if (ultimo != null) { ultimo.Dispose(); ultimo = null; } } }
}
"@
            Add-Type -TypeDefinition $codigoReceptor -ReferencedAssemblies @("System.Drawing", (Join-Path $Script:AForgeDir "AForge.Video.dll"), (Join-Path $Script:AForgeDir "AForge.dll")) -ErrorAction Stop
            $Script:ReceptorCamaraListo = $true
        } catch {
            Write-Log "No se pudo preparar el receptor de la camara: $($_.Exception.Message)" -Tipo ERROR
            return $false
        }
    }
    try { Ensure-TipoGdi } catch {}
    return $true
}

# Devuelve $false si Windows tiene bloqueado el acceso a la camara para apps de escritorio
# (Configuracion > Privacidad > Camara). Con eso bloqueado la camara "enciende" pero no llega imagen.
function Test-PermisoCamaraWindows {
    $claves = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam\NonPackaged',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
    )
    foreach ($clave in $claves) {
        try {
            $valor = (Get-ItemProperty -Path $clave -Name Value -ErrorAction Stop).Value
            if ("$valor" -eq 'Deny') { return $false }
        } catch {}
    }
    return $true
}

$Script:MensajeSinImagenCamara = "No llega imagen de la camara. Revisa: 1) Configuracion de Windows > Privacidad y seguridad > Camara: activa 'Acceso a la camara' y 'Permitir que las aplicaciones de escritorio accedan a la camara'. 2) Que ninguna otra app (Teams, Zoom, navegador) este usando la camara. 3) Que la camara no tenga el obturador/tapa fisica cerrada o este desactivada con una tecla Fn."

function Show-PruebaCamara {
    Write-DiagLog "=== CAMARA (vista previa en vivo propia) ==="
    if (-not (Initialize-ModuloCamara)) {
        Write-DiagLog "El modulo de camara no esta disponible (se descarga la primera vez y requiere internet; revisa el registro de actividad)."
        if (Show-Confirm "No se pudo preparar el modulo de camara propio (se descarga la primera vez y necesita internet).`n`n¿Quieres abrir la app Camara de Windows para probar la camara?" "Camara") {
            try { Start-Process "microsoft.windows.camera:" } catch {}
        }
        return
    }
    if (-not (Test-PermisoCamaraWindows)) {
        Write-DiagLog "AVISO: Windows tiene bloqueado el acceso a la camara para apps de escritorio (Configuracion > Privacidad > Camara)."
    }

    try {
        $dispositivos = New-Object AForge.Video.DirectShow.FilterInfoCollection([AForge.Video.DirectShow.FilterCategory]::VideoInputDevice)
        if ($dispositivos.Count -eq 0) {
            Write-DiagLog "No se detecto ninguna camara conectada."
            return
        }
        Write-DiagLog "Camara(s) detectada(s): $($dispositivos.Count)"
        for ($i = 0; $i -lt $dispositivos.Count; $i++) { Write-DiagLog " - $($dispositivos[$i].Name)" }

        [xml]$xamlCam = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Prueba de camara - The Dragon Tool" Height="560" Width="760" WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <DockPanel Margin="14">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Text="Si ves tu imagen en vivo, la camara funciona correctamente." Foreground="White" Margin="0,0,0,10"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnCerrarCamara" Content="Cerrar" Width="100"/>
    </StackPanel>
    <Border BorderBrush="#232B3D" BorderThickness="1" Background="#070A10">
      <Grid>
        <Image x:Name="ImgCamara" Stretch="Uniform"/>
        <TextBlock x:Name="TxtCamEstado" Text="Iniciando la camara..." Foreground="#66AEFF" TextWrapping="Wrap" TextAlignment="Center"
                   HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="520" FontSize="14"/>
      </Grid>
    </Border>
  </DockPanel>
</Window>
"@
        $readerCam = New-Object System.Xml.XmlNodeReader $xamlCam
        $winCam = [Windows.Markup.XamlReader]::Load($readerCam)
        Iniciar-EfectosNeon -Ventana $winCam
        $imgCtrl = $winCam.FindName("ImgCamara")
        $txtEstado = $winCam.FindName("TxtCamEstado")

        $receptor = New-Object DragonCamReceptor
        $videoSource = New-Object AForge.Video.DirectShow.VideoCaptureDevice($dispositivos[0].MonikerString)
        $receptor.Conectar($videoSource)
        $mensajeSinImagen = $Script:MensajeSinImagenCamara
        $est = @{ Inicio = (Get-Date); Frames = 0 }

        # Temporizador de la interfaz (~30 por segundo): toma el ultimo fotograma guardado por el
        # receptor y lo muestra. Todo esto corre en el hilo de la interfaz, donde PowerShell si funciona.
        $temporizador = New-Object System.Windows.Threading.DispatcherTimer
        $temporizador.Interval = [TimeSpan]::FromMilliseconds(33)
        $temporizador.Add_Tick({
            $bmp = $receptor.Tomar()
            if (-not $bmp) {
                if ($est.Frames -eq 0 -and ((Get-Date) - $est.Inicio).TotalSeconds -gt 6) {
                    $detalleError = if ($receptor.UltimoError) { "`n`nError reportado: $($receptor.UltimoError)" } else { "" }
                    $txtEstado.Text = $mensajeSinImagen + $detalleError
                }
                return
            }
            try {
                $hbitmap = $bmp.GetHbitmap()
                try {
                    $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($hbitmap, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                    $src.Freeze()
                    $imgCtrl.Source = $src
                } finally {
                    try { [DragonToolGdi]::DeleteObject($hbitmap) | Out-Null } catch {}
                }
                $est.Frames++
                if ($txtEstado.Visibility -ne 'Collapsed') { $txtEstado.Visibility = 'Collapsed' }
            } catch {} finally { $bmp.Dispose() }
        }.GetNewClosure())

        $videoSource.Start()
        $temporizador.Start()

        $winCam.Add_Closed({
            try { $temporizador.Stop() } catch {}
            try { $videoSource.SignalToStop(); $videoSource.WaitForStop() } catch {}
            try { $receptor.Liberar() } catch {}
        }.GetNewClosure())
        $winCam.FindName("BtnCerrarCamara").Add_Click({ $winCam.Close() })

        $winCam.ShowDialog() | Out-Null
        Write-DiagLog "Prueba de camara finalizada ($($est.Frames) fotogramas mostrados)."
    } catch {
        Write-DiagLog "No se pudo iniciar la prueba de camara: $($_.Exception.Message)"
    }
}

# --- Pestaña Modificacion: opcion Camara (vista en vivo embebida, con rotar/voltear) ---

$Script:ModCamVideoSource = $null
$Script:ModCamTemporizador = $null
$Global:DragonCamMod = $null
$Script:ModCamActiva = $false
$Script:ModCamRotacion = 0
$Script:ModCamFlipH = $false
$Script:ModCamFlipV = $false
$Script:ModCamDispositivos = $null
$Script:ModCamUltimoAncho = 0
$Script:ModCamUltimoAlto = 0
$Script:ModCamDetalleBase = ""

# Carga (o recarga) la lista de camaras detectadas en el ComboBox de la
# pestaña Modificacion. Prepara los componentes de camara (AForge) la
# primera vez que se usa, igual que la prueba de camara de Diagnostico.
function Global:Cargar-ListaCamarasModificacion {
    $cmb = $window.FindName("CmbModCamaraDispositivo")
    if (-not $cmb) { return }
    if (-not (Initialize-ModuloCamara)) {
        Write-Log "El modulo de camara no esta disponible (se descarga la primera vez y requiere internet; revisa el registro de actividad)." -Tipo ERROR
        return
    }
    try {
        $Script:ModCamDispositivos = New-Object AForge.Video.DirectShow.FilterInfoCollection([AForge.Video.DirectShow.FilterCategory]::VideoInputDevice)
        $nombres = @()
        for ($i = 0; $i -lt $Script:ModCamDispositivos.Count; $i++) { $nombres += $Script:ModCamDispositivos[$i].Name }
        $cmb.ItemsSource = $nombres
        if ($nombres.Count -gt 0) { $cmb.SelectedIndex = 0 }
        Write-Log "Camaras detectadas: $($nombres.Count)" -Tipo INFO
    } catch {
        Write-Log "No se pudo listar las camaras: $($_.Exception.Message)" -Tipo ERROR
    }
}

# Busca informacion adicional del dispositivo (fabricante, controlador) en
# Windows a partir de su nombre. Es solo informativo: si no se encuentra
# nada, la camara sigue funcionando igual.
function Global:Obtener-DetallesCamara {
    param([string]$Nombre)
    $lineas = New-Object System.Collections.Generic.List[string]
    $lineas.Add("Nombre: $Nombre")
    try {
        $pnp = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -and $Nombre -and ($_.Name -eq $Nombre -or $_.Name.Contains($Nombre) -or $Nombre.Contains($_.Name))
        } | Select-Object -First 1
        if ($pnp) {
            if ($pnp.Manufacturer) { $lineas.Add("Fabricante: $($pnp.Manufacturer)") }
            if ($pnp.Status) { $lineas.Add("Estado: $($pnp.Status)") }
            $driver = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $pnp.DeviceID } | Select-Object -First 1
            if ($driver) {
                if ($driver.DriverVersion) { $lineas.Add("Version del controlador: $($driver.DriverVersion)") }
                if ($driver.DriverProviderName) { $lineas.Add("Proveedor: $($driver.DriverProviderName)") }
                if ($driver.DriverDate) { $lineas.Add("Fecha del controlador: $($driver.DriverDate)") }
            }
        } else {
            $lineas.Add("(Windows no reporto mas detalles de este dispositivo)")
        }
    } catch {}
    return ($lineas -join "`r`n")
}

# Actualiza el panel de texto con los detalles + resolucion actual +
# orientacion (rotacion/volteo aplicados). Se llama al iniciar la camara,
# al cambiar la orientacion y cuando llega el primer fotograma.
function Global:Refrescar-DetallesCamaraModificacion {
    $txtDetalles = $window.FindName("TxtModCamaraDetalles")
    if (-not $txtDetalles) { return }
    $orientacion = if ($Script:ModCamRotacion -eq 0 -and -not $Script:ModCamFlipH -and -not $Script:ModCamFlipV) {
        "Normal (sin cambios)"
    } else {
        $partes = @()
        if ($Script:ModCamRotacion -ne 0) { $partes += "girada $($Script:ModCamRotacion) grados" }
        if ($Script:ModCamFlipH) { $partes += "volteada horizontalmente" }
        if ($Script:ModCamFlipV) { $partes += "volteada verticalmente" }
        $partes -join ", "
    }
    $resolucion = if ($Script:ModCamUltimoAncho -gt 0) { "$($Script:ModCamUltimoAncho) x $($Script:ModCamUltimoAlto) px" } else { "(esperando el primer fotograma...)" }
    $base = if ($Script:ModCamDetalleBase) { $Script:ModCamDetalleBase } else { "Camara detenida." }
    $txtDetalles.Text = "$base`r`n`r`nResolucion actual: $resolucion`r`nOrientacion: $orientacion"
}

# Aplica la rotacion/volteo actuales directamente sobre los pixeles del
# fotograma (no es un efecto visual de la ventana: la imagen realmente se
# gira/voltea), asi que se ve bien sin importar el tamaño del panel.
function Global:Aplicar-TransformCamara {
    param($Bitmap)
    switch ($Script:ModCamRotacion) {
        90  { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
        180 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
        270 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
        default {}
    }
    if ($Script:ModCamFlipH) { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
    if ($Script:ModCamFlipV) { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipY) }
}

# Se ejecuta ~30 veces por segundo en el hilo de la interfaz mientras la camara de Modificacion
# esta encendida: toma el ultimo fotograma que dejo el receptor (C#), le aplica rotar/voltear y lo muestra.
function Global:Actualizar-FotogramaCamaraModificacion {
    $cam = $Global:DragonCamMod
    if (-not $cam -or -not $cam.Receptor) { return }
    $bmp = $cam.Receptor.Tomar()
    if (-not $bmp) {
        if ($cam.Frames -eq 0 -and -not $cam.Avisado -and ((Get-Date) - $cam.Inicio).TotalSeconds -gt 6) {
            $cam.Avisado = $true
            $txtSinSenal = $window.FindName("TxtModCamaraSinSenal")
            if ($txtSinSenal) {
                $detalleError = if ($cam.Receptor.UltimoError) { "`n`nError reportado: $($cam.Receptor.UltimoError)" } else { "" }
                $txtSinSenal.Text = $Script:MensajeSinImagenCamara + $detalleError
                $txtSinSenal.MaxWidth = 420
                $txtSinSenal.Visibility = 'Visible'
            }
        }
        return
    }
    try {
        Aplicar-TransformCamara -Bitmap $bmp
        $esPrimerFotograma = ($Script:ModCamUltimoAncho -eq 0)
        $Script:ModCamUltimoAncho = $bmp.Width
        $Script:ModCamUltimoAlto = $bmp.Height
        $hbitmap = $bmp.GetHbitmap()
        try {
            $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($hbitmap, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
            $src.Freeze()
            $cam.Img.Source = $src
        } finally {
            try { [DragonToolGdi]::DeleteObject($hbitmap) | Out-Null } catch {}
        }
        $cam.Frames++
        if ($esPrimerFotograma) {
            $txtSinSenal = $window.FindName("TxtModCamaraSinSenal")
            if ($txtSinSenal) { $txtSinSenal.Visibility = 'Collapsed' }
            Refrescar-DetallesCamaraModificacion
        }
    } catch {} finally { $bmp.Dispose() }
}

function Global:Iniciar-CamaraModificacion {
    if ($Script:ModCamActiva) { return }
    if (-not (Initialize-ModuloCamara)) {
        Show-Aviso "No se pudo preparar el modulo de camara. Se descarga la primera vez y necesita conexion a internet (revisa el registro de actividad)." "Camara"
        return
    }
    if (-not $Script:ModCamDispositivos -or $Script:ModCamDispositivos.Count -eq 0) {
        Cargar-ListaCamarasModificacion
    }
    if (-not $Script:ModCamDispositivos -or $Script:ModCamDispositivos.Count -eq 0) {
        Show-Aviso "No se detecto ninguna camara conectada." "Sin camara"
        return
    }
    if (-not (Test-PermisoCamaraWindows)) {
        Write-Log "Windows tiene bloqueado el acceso a la camara para apps de escritorio (Configuracion > Privacidad > Camara)." -Tipo AVISO
    }

    $cmb = $window.FindName("CmbModCamaraDispositivo")
    $indice = if ($cmb -and $cmb.SelectedIndex -ge 0) { $cmb.SelectedIndex } else { 0 }
    $imgCtrl = $window.FindName("ImgModCamara")
    $txtSinSenal = $window.FindName("TxtModCamaraSinSenal")

    try {
        $dispositivoSeleccionado = $Script:ModCamDispositivos[$indice]
        $Script:ModCamUltimoAncho = 0
        $Script:ModCamUltimoAlto = 0
        $Script:ModCamDetalleBase = Obtener-DetallesCamara -Nombre $dispositivoSeleccionado.Name
        Refrescar-DetallesCamaraModificacion

        $receptor = New-Object DragonCamReceptor
        $videoSource = New-Object AForge.Video.DirectShow.VideoCaptureDevice($dispositivoSeleccionado.MonikerString)
        $receptor.Conectar($videoSource)

        # Estado compartido (global: lo lee la funcion que dibuja cada fotograma)
        $Global:DragonCamMod = @{ Receptor = $receptor; Img = $imgCtrl; Frames = 0; Inicio = (Get-Date); Avisado = $false }

        $temporizador = New-Object System.Windows.Threading.DispatcherTimer
        $temporizador.Interval = [TimeSpan]::FromMilliseconds(33)
        $temporizador.Add_Tick({ Actualizar-FotogramaCamaraModificacion })
        $videoSource.Start()
        $temporizador.Start()

        $Script:ModCamVideoSource = $videoSource
        $Script:ModCamTemporizador = $temporizador
        $Script:ModCamActiva = $true
        if ($txtSinSenal) {
            $txtSinSenal.Text = "Iniciando la camara..."
            $txtSinSenal.Visibility = 'Visible'
        }
        Write-Log "Camara de modificacion iniciada: $($dispositivoSeleccionado.Name)" -Tipo OK
    } catch {
        Write-Log "No se pudo iniciar la camara: $($_.Exception.Message)" -Tipo ERROR
        Show-Aviso "No se pudo iniciar la camara: $($_.Exception.Message)" "Error"
    }
}

function Global:Detener-CamaraModificacion {
    if ($Script:ModCamTemporizador) {
        try { $Script:ModCamTemporizador.Stop() } catch {}
        $Script:ModCamTemporizador = $null
    }
    if ($Script:ModCamVideoSource) {
        try { $Script:ModCamVideoSource.SignalToStop(); $Script:ModCamVideoSource.WaitForStop() } catch {}
        $Script:ModCamVideoSource = $null
    }
    if ($Global:DragonCamMod -and $Global:DragonCamMod.Receptor) {
        try { $Global:DragonCamMod.Receptor.Liberar() } catch {}
    }
    $Global:DragonCamMod = $null
    $Script:ModCamActiva = $false
    $Script:ModCamUltimoAncho = 0
    $Script:ModCamUltimoAlto = 0
    $Script:ModCamDetalleBase = ""
    $imgCtrl = $window.FindName("ImgModCamara")
    $txtSinSenal = $window.FindName("TxtModCamaraSinSenal")
    $txtDetalles = $window.FindName("TxtModCamaraDetalles")
    if ($imgCtrl) { $imgCtrl.Source = $null }
    if ($txtSinSenal) {
        $txtSinSenal.Text = "Camara detenida. Pulsa 'Iniciar camara'."
        $txtSinSenal.MaxWidth = 260
        $txtSinSenal.Visibility = 'Visible'
    }
    if ($txtDetalles) { $txtDetalles.Text = "Selecciona 'Iniciar camara' para ver aqui sus detalles (nombre, controlador, resolucion, orientacion actual)." }
    Write-Log "Camara de modificacion detenida." -Tipo INFO
}

# ---------------------------------------------------------------------------
#  PESTAÑA MODIFICACION: PANTALLA (frecuencia de actualizacion)
# ---------------------------------------------------------------------------

$Script:ModPantallaFrecPreferidaCA = 0
$Script:ModPantallaFrecPreferidaBateria = 0
$Script:ModPantallaAutoActivo = $false
$Script:ModPantallaUltimoEstadoEnergia = $null
$Script:TimerModPantallaEnergia = $null
$Script:ModPantallaFrecMaximaDetectada = 0

$Script:TipoDisplayListo = $false
function Ensure-TipoDisplay {
    if ($Script:TipoDisplayListo) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class DragonToolDisplay {
    public const int DM_DISPLAYFREQUENCY = 0x400000;
    public const int CDS_UPDATEREGISTRY = 0x01;
    private const int ENUM_CURRENT_SETTINGS = -1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplaySettingsW(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int ChangeDisplaySettingsExW(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    public static int ObtenerAnchoActual() {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettingsW(null, ENUM_CURRENT_SETTINGS, ref dm);
        return dm.dmPelsWidth;
    }

    public static int ObtenerAltoActual() {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettingsW(null, ENUM_CURRENT_SETTINGS, ref dm);
        return dm.dmPelsHeight;
    }

    public static int ObtenerFrecuenciaActual() {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettingsW(null, ENUM_CURRENT_SETTINGS, ref dm);
        return dm.dmDisplayFrequency;
    }

    public static int[] ObtenerFrecuenciasDisponibles() {
        DEVMODE actual = new DEVMODE();
        actual.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettingsW(null, ENUM_CURRENT_SETTINGS, ref actual);

        List<int> lista = new List<int>();
        int i = 0;
        while (true) {
            DEVMODE dm = new DEVMODE();
            dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettingsW(null, i, ref dm)) break;
            if (dm.dmPelsWidth == actual.dmPelsWidth && dm.dmPelsHeight == actual.dmPelsHeight && dm.dmDisplayFrequency > 1) {
                if (!lista.Contains(dm.dmDisplayFrequency)) lista.Add(dm.dmDisplayFrequency);
            }
            i++;
        }
        lista.Sort();
        return lista.ToArray();
    }

    public static int AplicarFrecuencia(int frecuencia) {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettingsW(null, ENUM_CURRENT_SETTINGS, ref dm);
        dm.dmDisplayFrequency = frecuencia;
        dm.dmFields = DM_DISPLAYFREQUENCY;
        return ChangeDisplaySettingsExW(null, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
    }
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoDisplayListo = $true
}

# Decodifica el nombre de modelo de un monitor a partir de su EDID (WmiMonitorID
# en el namespace root\wmi). Los datos vienen como arrays de codigos de caracter,
# no como texto directo.
function Global:Decodificar-CadenaEDID {
    param($Codigos)
    if (-not $Codigos) { return $null }
    $texto = -join ($Codigos | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
    return $texto.Trim()
}

function Global:Detectar-PantallaModificacion {
    $txt = $window.FindName("TxtModPantallaDetalles")
    $cmbDisp = $window.FindName("CmbModPantallaDispositivo")
    if (-not $txt) { return }
    $lineas = New-Object System.Collections.Generic.List[string]
    $pantallas = @()
    try {
        $monitores = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
        $i = 0
        foreach ($m in $monitores) {
            $i++
            $fabricante = Decodificar-CadenaEDID -Codigos $m.ManufacturerName
            $modelo = Decodificar-CadenaEDID -Codigos $m.UserFriendlyName
            $serie = Decodificar-CadenaEDID -Codigos $m.SerialNumberID
            $nombre = if ($modelo) { $modelo } else { "Pantalla $i" }
            $pantallas += [PSCustomObject]@{ Nombre = $nombre; Fabricante = $fabricante; Serie = $serie }
        }
    } catch {}

    if ($pantallas.Count -eq 0) {
        $pantallas = @([PSCustomObject]@{ Nombre = "Pantalla principal"; Fabricante = $null; Serie = $null })
    }
    if ($cmbDisp) {
        $cmbDisp.ItemsSource = @($pantallas | ForEach-Object { $_.Nombre })
        if ($pantallas.Count -gt 0) { $cmbDisp.SelectedIndex = 0 }
    }

    $esLaptop = $false
    try {
        $chasis = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PCSystemType
        $esLaptop = ($chasis -eq 2)
    } catch {}

    foreach ($p in $pantallas) {
        $lineas.Add("Nombre: $($p.Nombre)")
        if ($p.Fabricante) { $lineas.Add("Fabricante: $($p.Fabricante)") }
        if ($p.Serie) { $lineas.Add("Numero de serie: $($p.Serie)") }
    }
    if ($esLaptop) { $lineas.Add("`r`nEste equipo es una laptop: la pantalla detectada es normalmente el panel integrado.") }

    try {
        Ensure-TipoDisplay
        $ancho = [DragonToolDisplay]::ObtenerAnchoActual()
        $alto = [DragonToolDisplay]::ObtenerAltoActual()
        $frecActual = [DragonToolDisplay]::ObtenerFrecuenciaActual()
        $lineas.Add("`r`nResolucion actual: $ancho x $alto px")
        $lineas.Add("Frecuencia actual: $frecActual Hz")

        $frecuencias = [DragonToolDisplay]::ObtenerFrecuenciasDisponibles()
        $frecMaxima = if ($frecuencias.Count -gt 0) { ($frecuencias | Measure-Object -Maximum).Maximum } else { $frecActual }

        $panelFrec = $window.FindName("PanelModPantallaFrecuencia")
        $txtSin144 = $window.FindName("TxtModPantallaSin144")

        if ($frecMaxima -le 60) {
            # La pantalla (o el cable/adaptador/tarjeta grafica) no admite mas
            # de 60 Hz: no tiene sentido dejar elegir una frecuencia "fija",
            # asi que se oculta toda esa seccion y se avisa claramente.
            if ($panelFrec) { $panelFrec.Visibility = 'Collapsed' }
            if ($txtSin144) { $txtSin144.Visibility = 'Visible' }
            $Script:ModPantallaAutoActivo = $false
            if ($Script:TimerModPantallaEnergia) { $Script:TimerModPantallaEnergia.Stop() }
            Write-Log "Pantalla detectada: $ancho x $alto px, $frecActual Hz. No admite mas de 60 Hz: no se puede fijar una frecuencia distinta." -Tipo INFO
        } else {
            if ($panelFrec) { $panelFrec.Visibility = 'Visible' }
            if ($txtSin144) { $txtSin144.Visibility = 'Collapsed' }

            $cmbFrec = $window.FindName("CmbModPantallaFrecuencia")
            $cmbFrecCA = $window.FindName("CmbModPantallaFrecuenciaCA")
            $cmbFrecBateria = $window.FindName("CmbModPantallaFrecuenciaBateria")
            $itemsFrec = @($frecuencias | ForEach-Object { "$_ Hz" })
            if ($cmbFrec) {
                $cmbFrec.ItemsSource = $itemsFrec
                $indiceActual = [array]::IndexOf($frecuencias, $frecActual)
                $cmbFrec.SelectedIndex = if ($indiceActual -ge 0) { $indiceActual } else { 0 }
            }
            if ($cmbFrecCA) { $cmbFrecCA.ItemsSource = $itemsFrec; if ($itemsFrec.Count -gt 0) { $cmbFrecCA.SelectedIndex = 0 } }
            if ($cmbFrecBateria) { $cmbFrecBateria.ItemsSource = $itemsFrec; if ($itemsFrec.Count -gt 0) { $cmbFrecBateria.SelectedIndex = 0 } }
            $Script:ModPantallaFrecMaximaDetectada = $frecMaxima
            Write-Log "Pantalla detectada: $ancho x $alto px, $frecActual Hz. Frecuencias disponibles: $($frecuencias -join ', ') Hz." -Tipo OK
        }
    } catch {
        $lineas.Add("`r`n(No se pudo leer la frecuencia de actualizacion: $($_.Exception.Message))")
        Write-Log "No se pudo leer la informacion de frecuencia de la pantalla: $($_.Exception.Message)" -Tipo ERROR
    }

    $txt.Text = ($lineas -join "`r`n")
}

function Global:Accion-AplicarFrecuenciaPantalla {
    param([string]$TextoFrecuencia)
    if ([string]::IsNullOrWhiteSpace($TextoFrecuencia)) { return }
    $frec = [int]($TextoFrecuencia -replace '[^\d]', '')
    if ($frec -le 0) { return }
    try {
        Ensure-TipoDisplay
        $resultado = [DragonToolDisplay]::AplicarFrecuencia($frec)
        if ($resultado -eq 0) {
            Write-Log "Frecuencia de la pantalla cambiada a $frec Hz." -Tipo OK
        } else {
            Write-Log "Windows rechazo el cambio a $frec Hz (codigo $resultado). Puede que tu monitor o tarjeta grafica no lo admitan de forma estable." -Tipo AVISO
            Show-Aviso "Windows no acepto ese cambio de frecuencia (codigo $resultado). Prueba con otra de la lista." "No se pudo aplicar"
        }
    } catch {
        Write-Log "No se pudo cambiar la frecuencia de la pantalla: $($_.Exception.Message)" -Tipo ERROR
    }
}

# Revisa la fuente de energia actual (cargador/bateria) y, si cambio desde la
# ultima revision, aplica la frecuencia guardada para esa fuente. Solo actua
# mientras The Dragon Tool esta abierto: no es un servicio de Windows.
function Global:Revisar-EnergiaPantallaModificacion {
    if (-not $Script:ModPantallaAutoActivo) { return }
    try {
        $estado = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString()
    } catch { return }
    if ($estado -eq $Script:ModPantallaUltimoEstadoEnergia) { return }
    $Script:ModPantallaUltimoEstadoEnergia = $estado
    $frecObjetivo = if ($estado -eq 'Online') { $Script:ModPantallaFrecPreferidaCA } else { $Script:ModPantallaFrecPreferidaBateria }
    if ($frecObjetivo -gt 0) {
        Accion-AplicarFrecuenciaPantalla -TextoFrecuencia "$frecObjetivo Hz"
        Write-Log "Fuente de energia cambiada ($estado): frecuencia de pantalla ajustada a $frecObjetivo Hz." -Tipo INFO
    }
}

# ---------------------------------------------------------------------------
#  PESTAÑA MODIFICACION: TECLADO (remapeo y bloqueo de teclas)
# ---------------------------------------------------------------------------

# Codigos de escaneo (scan codes) estandar de teclado, en el mismo formato que
# usa el "Scancode Map" del registro de Windows: 0x00XX para teclas normales,
# 0xE0XX para teclas extendidas (flechas, Win, Ctrl/Alt derechos, etc.).
$Script:MapaScanCodes = @{
    'Escape'=0x0001; 'F1'=0x003B; 'F2'=0x003C; 'F3'=0x003D; 'F4'=0x003E; 'F5'=0x003F; 'F6'=0x0040
    'F7'=0x0041; 'F8'=0x0042; 'F9'=0x0043; 'F10'=0x0044; 'F11'=0x0057; 'F12'=0x0058
    'OemTilde'=0x0029; 'D1'=0x0002; 'D2'=0x0003; 'D3'=0x0004; 'D4'=0x0005; 'D5'=0x0006
    'D6'=0x0007; 'D7'=0x0008; 'D8'=0x0009; 'D9'=0x000A; 'D0'=0x000B
    'OemMinus'=0x000C; 'OemPlus'=0x000D; 'Back'=0x000E
    'Tab'=0x000F; 'Q'=0x0010; 'W'=0x0011; 'E'=0x0012; 'R'=0x0013; 'T'=0x0014; 'Y'=0x0015; 'U'=0x0016
    'I'=0x0017; 'O'=0x0018; 'P'=0x0019; 'OemOpenBrackets'=0x001A; 'OemCloseBrackets'=0x001B; 'OemBackslash'=0x002B
    'CapsLock'=0x003A; 'A'=0x001E; 'S'=0x001F; 'D'=0x0020; 'F'=0x0021; 'G'=0x0022; 'H'=0x0023
    'J'=0x0024; 'K'=0x0025; 'L'=0x0026; 'OemSemicolon'=0x0027; 'OemQuotes'=0x0028; 'Return'=0x001C
    'LeftShift'=0x002A; 'Z'=0x002C; 'X'=0x002D; 'C'=0x002E; 'V'=0x002F; 'B'=0x0030; 'N'=0x0031; 'M'=0x0032
    'OemComma'=0x0033; 'OemPeriod'=0x0034; 'OemQuestion'=0x0035; 'RightShift'=0x0036
    'LeftCtrl'=0x001D; 'LWin'=0xE05B; 'LeftAlt'=0x0038; 'Space'=0x0039
    'RightAlt'=0xE038; 'RWin'=0xE05C; 'RightCtrl'=0xE01D
    'Left'=0xE04B; 'Up'=0xE048; 'Down'=0xE050; 'Right'=0xE04D
    'Insert'=0xE052; 'Delete'=0xE053; 'Home'=0xE047; 'End'=0xE04F; 'PageUp'=0xE049; 'PageDown'=0xE051
    'NumLock'=0x0045; 'Scroll'=0x0046
    'VolumeMute'=0xE020; 'VolumeDown'=0xE02E; 'VolumeUp'=0xE030
    'MediaPlayPause'=0xE022; 'MediaStop'=0xE024; 'MediaNextTrack'=0xE019; 'MediaPreviousTrack'=0xE010
}
$Script:EtiquetasTeclasModificacion = @{
    'Escape'='Esc'; 'F1'='F1'; 'F2'='F2'; 'F3'='F3'; 'F4'='F4'; 'F5'='F5'; 'F6'='F6'; 'F7'='F7'; 'F8'='F8'; 'F9'='F9'; 'F10'='F10'; 'F11'='F11'; 'F12'='F12'
    'OemTilde'='`'; 'D1'='1'; 'D2'='2'; 'D3'='3'; 'D4'='4'; 'D5'='5'; 'D6'='6'; 'D7'='7'; 'D8'='8'; 'D9'='9'; 'D0'='0'
    'OemMinus'='-'; 'OemPlus'='='; 'Back'='Backspace'
    'Tab'='Tab'; 'Q'='Q'; 'W'='W'; 'E'='E'; 'R'='R'; 'T'='T'; 'Y'='Y'; 'U'='U'; 'I'='I'; 'O'='O'; 'P'='P'
    'OemOpenBrackets'='['; 'OemCloseBrackets'=']'; 'OemBackslash'='\'
    'CapsLock'='Bloq Mayus'; 'A'='A'; 'S'='S'; 'D'='D'; 'F'='F'; 'G'='G'; 'H'='H'; 'J'='J'; 'K'='K'; 'L'='L'
    'OemSemicolon'=';'; 'OemQuotes'="'"; 'Return'='Enter'
    'LeftShift'='Shift izq.'; 'Z'='Z'; 'X'='X'; 'C'='C'; 'V'='V'; 'B'='B'; 'N'='N'; 'M'='M'
    'OemComma'=','; 'OemPeriod'='.'; 'OemQuestion'='/'; 'RightShift'='Shift der.'
    'LeftCtrl'='Ctrl izq.'; 'LWin'='Win izq.'; 'LeftAlt'='Alt izq.'; 'Space'='Espacio'
    'RightAlt'='Alt der.'; 'RWin'='Win der.'; 'RightCtrl'='Ctrl der.'
    'Left'='Flecha izq.'; 'Up'='Flecha arriba'; 'Down'='Flecha abajo'; 'Right'='Flecha der.'
    'Insert'='Insert'; 'Delete'='Supr'; 'Home'='Inicio'; 'End'='Fin'; 'PageUp'='Re Pag'; 'PageDown'='Av Pag'
    'NumLock'='Bloq Num'; 'Scroll'='Bloq Despl'
    'VolumeMute'='Silenciar volumen'; 'VolumeDown'='Bajar volumen'; 'VolumeUp'='Subir volumen'
    'MediaPlayPause'='Reproducir/Pausa'; 'MediaStop'='Detener'; 'MediaNextTrack'='Siguiente pista'; 'MediaPreviousTrack'='Pista anterior'
}
function Global:Etiqueta-TeclaModificacion {
    param([string]$NombreTecla)
    if ($Script:EtiquetasTeclasModificacion.ContainsKey($NombreTecla)) { return $Script:EtiquetasTeclasModificacion[$NombreTecla] }
    return $NombreTecla
}

$Script:ModTecladoMapeos = New-Object System.Collections.ArrayList
$Script:ModTecladoTeclaSeleccionada = $null
$Script:ModTecladoBordesVisuales = @{}

# Dibuja el teclado virtual (solo visual, de referencia) dentro del panel de
# la pestaña Modificacion, reutilizando la misma distribucion de teclas de la
# prueba de teclado de Diagnostico.
function Global:Construir-TecladoVisualModificacion {
    $panel = $window.FindName("PanelModTecladoVisual")
    if (-not $panel -or $panel.Children.Count -gt 0) { return }
    $filas = @(
        @(@{L='Esc';K='Escape'},@{L='F1';K='F1'},@{L='F2';K='F2'},@{L='F3';K='F3'},@{L='F4';K='F4'},@{L='F5';K='F5'},@{L='F6';K='F6'},@{L='F7';K='F7'},@{L='F8';K='F8'},@{L='F9';K='F9'},@{L='F10';K='F10'},@{L='F11';K='F11'},@{L='F12';K='F12'}),
        @(@{L='`';K='OemTilde'},@{L='1';K='D1'},@{L='2';K='D2'},@{L='3';K='D3'},@{L='4';K='D4'},@{L='5';K='D5'},@{L='6';K='D6'},@{L='7';K='D7'},@{L='8';K='D8'},@{L='9';K='D9'},@{L='0';K='D0'},@{L='-';K='OemMinus'},@{L='=';K='OemPlus'},@{L='Backspace';K='Back';W=2}),
        @(@{L='Tab';K='Tab';W=1.5},@{L='Q';K='Q'},@{L='W';K='W'},@{L='E';K='E'},@{L='R';K='R'},@{L='T';K='T'},@{L='Y';K='Y'},@{L='U';K='U'},@{L='I';K='I'},@{L='O';K='O'},@{L='P';K='P'},@{L='[';K='OemOpenBrackets'},@{L=']';K='OemCloseBrackets'},@{L='\';K='OemBackslash';W=1.5}),
        @(@{L='Caps';K='CapsLock';W=1.75},@{L='A';K='A'},@{L='S';K='S'},@{L='D';K='D'},@{L='F';K='F'},@{L='G';K='G'},@{L='H';K='H'},@{L='J';K='J'},@{L='K';K='K'},@{L='L';K='L'},@{L=';';K='OemSemicolon'},@{L="'";K='OemQuotes'},@{L='Enter';K='Return';W=2.25}),
        @(@{L='Shift';K='LeftShift';W=2.25},@{L='Z';K='Z'},@{L='X';K='X'},@{L='C';K='C'},@{L='V';K='V'},@{L='B';K='B'},@{L='N';K='N'},@{L='M';K='M'},@{L=',';K='OemComma'},@{L='.';K='OemPeriod'},@{L='/';K='OemQuestion'},@{L='Shift';K='RightShift';W=2.75}),
        @(@{L='Ctrl';K='LeftCtrl';W=1.5},@{L='Win';K='LWin';W=1.25},@{L='Alt';K='LeftAlt';W=1.25},@{L='Espacio';K='Space';W=6.5},@{L='Alt';K='RightAlt';W=1.25},@{L='Win';K='RWin';W=1.25},@{L='Ctrl';K='RightCtrl';W=1.5}),
        @(@{L='←';K='Left'},@{L='↑';K='Up'},@{L='↓';K='Down'},@{L='→';K='Right'})
    )
    $colorNormal = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#151B27")
    $bordeNormal = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#232B3D")
    foreach ($fila in $filas) {
        $filaPanel = New-Object System.Windows.Controls.StackPanel
        $filaPanel.Orientation = "Horizontal"
        $filaPanel.HorizontalAlignment = "Center"
        $filaPanel.Margin = "0,2,0,2"
        foreach ($tecla in $fila) {
            $ancho = 40
            if ($tecla.W) { $ancho = 40 * [double]$tecla.W }
            $border = New-Object System.Windows.Controls.Border
            $border.Width = $ancho
            $border.Height = 34
            $border.Margin = "1.5"
            $border.CornerRadius = 5
            $border.Background = $colorNormal
            $border.BorderBrush = $bordeNormal
            $border.BorderThickness = 1
            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = $tecla.L
            $txt.Foreground = [System.Windows.Media.Brushes]::White
            $txt.FontSize = 10
            $txt.HorizontalAlignment = "Center"
            $txt.VerticalAlignment = "Center"
            $border.Child = $txt
            $filaPanel.Children.Add($border) | Out-Null
            $Script:ModTecladoBordesVisuales[$tecla.K] = $border
        }
        $panel.Children.Add($filaPanel) | Out-Null
    }
}

function Global:Seleccionar-TeclaOrigenModificacion {
    param([string]$NombreTecla)
    if (-not $Script:MapaScanCodes.ContainsKey($NombreTecla)) { return }
    $colorNormal = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#151B27")
    $colorSeleccionado = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2F7CF6")
    foreach ($k in $Script:ModTecladoBordesVisuales.Keys) { $Script:ModTecladoBordesVisuales[$k].Background = $colorNormal }
    if ($Script:ModTecladoBordesVisuales.ContainsKey($NombreTecla)) { $Script:ModTecladoBordesVisuales[$NombreTecla].Background = $colorSeleccionado }
    $Script:ModTecladoTeclaSeleccionada = $NombreTecla
    $txt = $window.FindName("TxtModTecladoSeleccionada")
    if ($txt) { $txt.Text = "Tecla seleccionada: $(Etiqueta-TeclaModificacion -NombreTecla $NombreTecla)" }
}

function Global:Detectar-TecladosModificacion {
    $txt = $window.FindName("TxtModTecladoDetectado")
    $cmbTipo = $window.FindName("CmbModTecladoTipo")
    if (-not $txt) { return }
    try {
        $teclados = @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue)
        if ($teclados.Count -eq 0) {
            $txt.Text = "No se detecto informacion de teclado en Windows (puede seguir funcionando igual)."
            return
        }
        $lineas = @()
        $tipoDetectado = $null
        foreach ($t in $teclados) {
            $id = "$($t.DeviceID)$($t.PNPDeviceID)"
            $tipo = if ($id -match '^ACPI') { 'Laptop (integrado)' } elseif ($id -match 'USB') { 'USB' } else { 'PC (cable/PS2)' }
            if (-not $tipoDetectado) { $tipoDetectado = $tipo }
            $lineas += "$($t.Description) - Tipo detectado: $tipo"
        }
        $txt.Text = ($lineas -join "`r`n")
        if ($cmbTipo -and $tipoDetectado) {
            foreach ($item in $cmbTipo.Items) {
                if ("$($item.Content)" -eq $tipoDetectado) { $cmbTipo.SelectedItem = $item; break }
            }
        }
        Write-Log "Teclado(s) detectado(s): $($teclados.Count)." -Tipo OK
    } catch {
        $txt.Text = "No se pudo detectar el teclado: $($_.Exception.Message)"
    }
}

function Global:Agregar-MapeoTecladoModificacion {
    if (-not $Script:ModTecladoTeclaSeleccionada) {
        Show-Aviso "Primero haz clic en el area del teclado virtual y presiona la tecla fisica que quieras cambiar." "Ninguna tecla seleccionada"
        return
    }
    $chkBloquear = $window.FindName("ChkModTecladoBloquear")
    $cmbDestino = $window.FindName("CmbModTecladoDestino")
    $origen = $Script:ModTecladoTeclaSeleccionada
    $origenScan = $Script:MapaScanCodes[$origen]
    $origenEtiqueta = Etiqueta-TeclaModificacion -NombreTecla $origen

    if ($chkBloquear -and $chkBloquear.IsChecked) {
        $destinoScan = 0x0000
        $destinoEtiqueta = "Bloqueada (no hace nada)"
    } else {
        if (-not $cmbDestino -or -not $cmbDestino.SelectedItem) {
            Show-Aviso "Elige a que tecla o funcion se debe reasignar, o marca 'Bloquear esta tecla'." "Falta el destino"
            return
        }
        $destinoNombre = $cmbDestino.SelectedItem.Tag
        $destinoScan = $Script:MapaScanCodes[$destinoNombre]
        $destinoEtiqueta = $cmbDestino.SelectedItem.Content
    }

    # Si ya habia un mapeo para esta misma tecla origen, se reemplaza en vez de duplicarlo.
    $existente = $Script:ModTecladoMapeos | Where-Object { $_.OrigenKey -eq $origen } | Select-Object -First 1
    if ($existente) { $Script:ModTecladoMapeos.Remove($existente) }

    [void]$Script:ModTecladoMapeos.Add([PSCustomObject]@{
        OrigenKey       = $origen
        OrigenEtiqueta  = $origenEtiqueta
        OrigenScan      = $origenScan
        DestinoEtiqueta = $destinoEtiqueta
        DestinoScan     = $destinoScan
    })
    Actualizar-GridMapeosTeclado
}

function Global:Actualizar-GridMapeosTeclado {
    $grid = $window.FindName("GridModTecladoMapeos")
    if ($grid) { $grid.ItemsSource = $null; $grid.ItemsSource = @($Script:ModTecladoMapeos) }
}

function Global:Construir-BytesScancodeMap {
    param($Mapeos)
    $lista = New-Object System.Collections.Generic.List[byte]
    $lista.AddRange([byte[]]@(0,0,0,0))
    $lista.AddRange([byte[]]@(0,0,0,0))
    $lista.AddRange([System.BitConverter]::GetBytes([uint32]($Mapeos.Count + 1)))
    foreach ($m in $Mapeos) {
        $lista.AddRange([System.BitConverter]::GetBytes([uint16]$m.DestinoScan))
        $lista.AddRange([System.BitConverter]::GetBytes([uint16]$m.OrigenScan))
    }
    $lista.AddRange([byte[]]@(0,0,0,0))
    return $lista.ToArray()
}

function Global:Accion-AplicarMapeosTeclado {
    if ($Script:ModTecladoMapeos.Count -eq 0) { Show-Aviso "No has agregado ningun cambio a la lista todavia." "Lista vacia"; return }
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Se guardaran $($Script:ModTecladoMapeos.Count) cambio(s) de teclado en Windows. IMPORTANTE: solo se activan despues de REINICIAR el equipo (es asi como funciona el remapeo de teclado en Windows). ¿Continuar?")) { return }
    try {
        $bytes = Construir-BytesScancodeMap -Mapeos $Script:ModTecladoMapeos
        $ruta = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout"
        New-ItemProperty -Path $ruta -Name "Scancode Map" -PropertyType Binary -Value $bytes -Force | Out-Null
        Write-Log "Remapeo de teclado guardado ($($Script:ModTecladoMapeos.Count) cambio(s)). Se activara al reiniciar el equipo." -Tipo OK
        Show-Aviso "Cambios guardados. Reinicia el equipo para que se activen." "Listo"
    } catch {
        Write-Log "No se pudo guardar el remapeo de teclado: $($_.Exception.Message)" -Tipo ERROR
        Show-Aviso "No se pudo guardar: $($_.Exception.Message)" "Error"
    }
}

function Global:Accion-QuitarMapeosTeclado {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Se quitaran todas las reasignaciones de teclas guardadas en Windows (vuelve todo a la normalidad). Se activa al reiniciar el equipo. ¿Continuar?")) { return }
    try {
        $ruta = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout"
        Remove-ItemProperty -Path $ruta -Name "Scancode Map" -ErrorAction SilentlyContinue
        $Script:ModTecladoMapeos.Clear()
        Actualizar-GridMapeosTeclado
        Write-Log "Remapeo de teclado eliminado. Se normalizara al reiniciar el equipo." -Tipo OK
        Show-Aviso "Reasignaciones eliminadas. Reinicia el equipo para que se normalice." "Listo"
    } catch {
        Write-Log "No se pudo quitar el remapeo de teclado: $($_.Exception.Message)" -Tipo ERROR
    }
}

# ---------------------------------------------------------------------------
#  PESTAÑA MODIFICACION: PARLANTE (deteccion y volumen)
# ---------------------------------------------------------------------------

$Script:TipoAudioListo = $false
function Ensure-TipoAudio {
    if ($Script:TipoAudioListo) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDragonAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out int pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);
    int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(uint nChannel, float fLevelDB, Guid pguidEventContext);
    int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, Guid pguidEventContext);
    int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    int SetMute(bool bMute, Guid pguidEventContext);
    int GetMute(out bool pbMute);
    int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    int VolumeStepUp(Guid pguidEventContext);
    int VolumeStepDown(Guid pguidEventContext);
    int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDragonMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
    int GetId(out IntPtr ppstrId);
    int GetState(out int pdwState);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDragonMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IDragonMMDevice ppEndpoint);
    int GetDevice(string pwstrId, out IDragonMMDevice ppDevice);
    int RegisterEndpointNotificationCallback(IntPtr pClient);
    int UnregisterEndpointNotificationCallback(IntPtr pClient);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class DragonMMDeviceEnumeratorComObject { }

public class DragonToolAudio {
    private static IDragonAudioEndpointVolume ObtenerVolumenEndpoint() {
        IDragonMMDeviceEnumerator enumerador = (IDragonMMDeviceEnumerator)(new DragonMMDeviceEnumeratorComObject());
        IDragonMMDevice dispositivo;
        enumerador.GetDefaultAudioEndpoint(0, 1, out dispositivo);
        Guid iid = typeof(IDragonAudioEndpointVolume).GUID;
        object obj;
        dispositivo.Activate(ref iid, 1, IntPtr.Zero, out obj);
        return (IDragonAudioEndpointVolume)obj;
    }

    public static float ObtenerVolumenActual() {
        float nivel;
        ObtenerVolumenEndpoint().GetMasterVolumeLevelScalar(out nivel);
        return nivel;
    }

    public static void EstablecerVolumen(float nivel0a1) {
        ObtenerVolumenEndpoint().SetMasterVolumeLevelScalar(nivel0a1, Guid.Empty);
    }

    public static bool ObtenerSilenciado() {
        bool mute;
        ObtenerVolumenEndpoint().GetMute(out mute);
        return mute;
    }

    public static void EstablecerSilenciado(bool silenciar) {
        ObtenerVolumenEndpoint().SetMute(silenciar, Guid.Empty);
    }
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoAudioListo = $true
}

$Script:ModParlanteActualizandoUI = $false

function Global:Detectar-ParlantesModificacion {
    $txt = $window.FindName("TxtModParlanteDetalles")
    $panelOpc = $window.FindName("PanelModParlanteOpciones")
    if (-not $txt) { return }
    $lineas = New-Object System.Collections.Generic.List[string]
    try {
        $dispositivos = @(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)
        if ($dispositivos.Count -eq 0) {
            $lineas.Add("No se detecto ningun dispositivo de audio.")
        } else {
            foreach ($d in $dispositivos) {
                $lineas.Add("Nombre: $($d.Name)")
                if ($d.Manufacturer) { $lineas.Add("Fabricante: $($d.Manufacturer)") }
                if ($d.Status) { $lineas.Add("Estado: $($d.Status)") }
                $lineas.Add("")
            }
        }
    } catch {
        $lineas.Add("No se pudo consultar los dispositivos de audio: $($_.Exception.Message)")
    }

    try {
        Ensure-TipoAudio
        $nivel = [DragonToolAudio]::ObtenerVolumenActual()
        $silenciado = [DragonToolAudio]::ObtenerSilenciado()
        $porcentaje = [math]::Round($nivel * 100)
        $Script:ModParlanteActualizandoUI = $true
        $slider = $window.FindName("SliderModParlanteVolumen")
        $txtVol = $window.FindName("TxtModParlanteVolumenValor")
        $chkMute = $window.FindName("ChkModParlanteSilenciar")
        if ($slider) { $slider.Value = $porcentaje }
        if ($txtVol) { $txtVol.Text = "$porcentaje%" }
        if ($chkMute) { $chkMute.IsChecked = $silenciado }
        $Script:ModParlanteActualizandoUI = $false
        if ($panelOpc) { $panelOpc.Visibility = 'Visible' }
        Write-Log "Volumen actual del sistema: $porcentaje%$(if ($silenciado) { ' (silenciado)' })." -Tipo OK
    } catch {
        $lineas.Add("`r`n(No se pudo leer el volumen del sistema: $($_.Exception.Message))")
        Write-Log "No se pudo leer el volumen del sistema: $($_.Exception.Message)" -Tipo ERROR
    }

    $txt.Text = ($lineas -join "`r`n")
    Detectar-EqualizerAPOModificacion
}

# --- Amplificacion real por encima del 100%, via Equalizer APO ---
# La API de volumen de Windows (IAudioEndpointVolume) solo permite de 0% a
# 100%: eso es un limite del propio Windows, no del programa. Para superar
# ese limite de verdad hace falta agregar ganancia (dB) ANTES de que el audio
# llegue a la tarjeta de sonido, y eso solo lo hace un componente de
# procesamiento de audio instalado en el sistema. Equalizer APO es la
# herramienta gratuita y de codigo abierto mas usada para esto: se integra
# con el propio motor de audio de Windows y expone su ganancia ("Preamp") en
# un archivo de configuracion de texto plano, que es justo lo que este panel
# lee y escribe para dar el control deslizante de amplificacion.
$Script:RutaConfigEqualizerAPO = "$env:ProgramFiles\EqualizerAPO\config\config.txt"

function Global:Detectar-EqualizerAPOModificacion {
    $txtEstado = $window.FindName("TxtModParlanteEstadoAPO")
    $slider = $window.FindName("SliderModParlanteAmplificacion")
    $txtValor = $window.FindName("TxtModParlanteAmplificacionValor")
    if (-not $txtEstado) { return }
    if (Test-Path $Script:RutaConfigEqualizerAPO) {
        $txtEstado.Text = "Equalizer APO detectado. Mueve el control para amplificar el volumen del sistema al instante."
        $porcentajeActual = 100
        try {
            $contenido = Get-Content -Path $Script:RutaConfigEqualizerAPO -ErrorAction Stop
            $lineaPreamp = $contenido | Where-Object { $_ -match '^\s*Preamp\s*:' } | Select-Object -First 1
            if ($lineaPreamp -match '([\-\d\.]+)\s*dB') {
                $db = [double]$Matches[1]
                $porcentajeActual = [math]::Round([math]::Pow(10, $db / 20) * 100)
            }
        } catch {}
        $porcentajeActual = [math]::Max(100, [math]::Min(400, $porcentajeActual))
        $Script:ModParlanteActualizandoUI = $true
        if ($slider) { $slider.IsEnabled = $true; $slider.Value = $porcentajeActual }
        if ($txtValor) { $txtValor.Text = "$porcentajeActual%" }
        $Script:ModParlanteActualizandoUI = $false
    } else {
        $txtEstado.Text = "Equalizer APO no detectado todavia. Instalalo primero con el boton de arriba (una sola vez; pide reiniciar el equipo)."
        if ($slider) { $slider.IsEnabled = $false }
    }
}

function Global:Accion-InstalarEqualizerAPO {
    Write-Log "Abriendo la pagina oficial de Equalizer APO para instalarlo..." -Tipo INFO
    Show-VentanaNavegador -Url "https://sourceforge.net/projects/equalizerapo/" -Titulo "Instalar Equalizer APO" -TextoRespaldo "Equalizer APO download"
    Show-Aviso "Descarga e instala Equalizer APO desde la pagina que se abrio (boton verde 'Download'). Durante su instalador, marca la casilla de tu dispositivo de salida (parlantes o audifonos). Al terminar, reinicia el equipo una sola vez. Despues de eso vuelve a esta pestaña y pulsa 'Detectar parlantes': el control de amplificacion ya va a funcionar." "Instalar Equalizer APO"
}

function Global:Accion-AplicarAmplificacionParlante {
    param([int]$Porcentaje)
    if (-not (Test-Path $Script:RutaConfigEqualizerAPO)) { return }
    if (-not (Requiere-Admin)) { return }
    try {
        $db = 20 * [math]::Log10([math]::Max($Porcentaje, 1) / 100.0)
        $dbTexto = [math]::Round($db, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $lineaNueva = "Preamp: $dbTexto dB"
        $contenido = @(Get-Content -Path $Script:RutaConfigEqualizerAPO -ErrorAction SilentlyContinue)
        $yaExiste = $false
        $contenidoNuevo = @(
            foreach ($linea in $contenido) {
                if ($linea -match '^\s*Preamp\s*:') { $yaExiste = $true; $lineaNueva } else { $linea }
            }
        )
        if (-not $yaExiste) { $contenidoNuevo = @($lineaNueva) + $contenidoNuevo }
        Set-Content -Path $Script:RutaConfigEqualizerAPO -Value $contenidoNuevo -Encoding UTF8 -ErrorAction Stop
        Write-Log "Amplificacion de audio ajustada a $Porcentaje% ($dbTexto dB) via Equalizer APO." -Tipo OK
    } catch {
        Write-Log "No se pudo ajustar la amplificacion: $($_.Exception.Message)" -Tipo ERROR
        Show-Aviso "No se pudo escribir la configuracion de Equalizer APO: $($_.Exception.Message)" "Error"
    }
}

function Global:Accion-BoosterVolumenModificacion {
    try {
        Ensure-TipoAudio
        [DragonToolAudio]::EstablecerVolumen(1.0)
        [DragonToolAudio]::EstablecerSilenciado($false)
        $slider = $window.FindName("SliderModParlanteVolumen")
        $txtVol = $window.FindName("TxtModParlanteVolumenValor")
        $chkMute = $window.FindName("ChkModParlanteSilenciar")
        $Script:ModParlanteActualizandoUI = $true
        if ($slider) { $slider.Value = 100 }
        if ($txtVol) { $txtVol.Text = "100%" }
        if ($chkMute) { $chkMute.IsChecked = $false }
        $Script:ModParlanteActualizandoUI = $false
        Write-Log "Volumen del sistema al maximo (100%)." -Tipo OK
        Show-Aviso "Volumen al 100% (el maximo que Windows permite de forma nativa sin hardware o software adicional de amplificacion)." "Volumen maximizado"
    } catch {
        Write-Log "No se pudo maximizar el volumen: $($_.Exception.Message)" -Tipo ERROR
    }
}

# --- Pestaña Modificacion: Almacenamiento ---
$Script:ModAlmacenamientoDispositivos = @()

function Global:Clasificar-TipoAlmacenamiento {
    param($Disco)
    $bus = "$($Disco.BusType)"
    $media = "$($Disco.MediaType)"
    $nombre = "$($Disco.FriendlyName)"
    if ($nombre -match '(?i)micro ?sd') { return 'Tarjeta microSD' }
    if ($nombre -match '(?i)\bsd\b|sd card|tarjeta') { return 'Tarjeta SD' }
    if ($bus -match '(?i)^SD$|MMC') { return 'Tarjeta SD/microSD' }
    if ($bus -match '(?i)USB') { return 'Pendrive USB' }
    if ($media -match '(?i)SSD') { return 'SSD' }
    if ($media -match '(?i)HDD') { return 'HDD' }
    if ($bus -match '(?i)NVMe') { return 'SSD (NVMe)' }
    return 'Almacenamiento'
}

function Global:Detectar-AlmacenamientoModificacion {
    $cmb = $window.FindName("CmbModAlmacenamientoDispositivo")
    $txt = $window.FindName("TxtModAlmacenamientoDetalles")
    $txtFw = $window.FindName("TxtModAlmacenamientoFirmware")
    $txtR = $window.FindName("TxtModAlmacenamientoResultadoErrores")
    if (-not $cmb) { return }
    $cmb.Items.Clear()
    $Script:ModAlmacenamientoDispositivos = @()
    if ($txtR) { $txtR.Text = "Todavia no se ha ejecutado ningun analisis." }
    try {
        $discos = @(Get-PhysicalDisk -ErrorAction Stop)
    } catch {
        Write-Log "No se pudo enumerar el almacenamiento: $($_.Exception.Message)" -Tipo ERROR
        if ($txt) { $txt.Text = "No se pudo enumerar el almacenamiento en este equipo: $($_.Exception.Message)" }
        return
    }
    if ($discos.Count -eq 0) {
        if ($txt) { $txt.Text = "No se detecto ningun disco, pendrive o tarjeta de memoria conectada." }
        return
    }
    $Script:ModAlmacenamientoDispositivos = $discos
    foreach ($d in $discos) {
        $tipo = Clasificar-TipoAlmacenamiento -Disco $d
        $tamanoGB = if ($d.Size) { [math]::Round($d.Size / 1GB, 1) } else { 0 }
        $etiqueta = "$tipo - $($d.FriendlyName) ($tamanoGB GB)"
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $etiqueta
        $cmb.Items.Add($item) | Out-Null
    }
    Write-Log "Almacenamiento detectado: $($discos.Count) dispositivo(s)." -Tipo OK
    if ($cmb.Items.Count -gt 0) {
        $cmb.SelectedIndex = 0
    } elseif ($txt) {
        $txt.Text = "Pulsa 'Detectar almacenamiento' y luego selecciona un dispositivo de la lista para ver aqui su informacion detallada."
    }
}

function Global:Obtener-AlmacenamientoSeleccionado {
    $cmb = $window.FindName("CmbModAlmacenamientoDispositivo")
    if (-not $cmb -or $cmb.SelectedIndex -lt 0) { return $null }
    $idx = $cmb.SelectedIndex
    if ($idx -ge $Script:ModAlmacenamientoDispositivos.Count) { return $null }
    return $Script:ModAlmacenamientoDispositivos[$idx]
}

function Global:Mostrar-DetalleAlmacenamientoSeleccionado {
    $txt = $window.FindName("TxtModAlmacenamientoDetalles")
    $txtFw = $window.FindName("TxtModAlmacenamientoFirmware")
    $d = Obtener-AlmacenamientoSeleccionado
    if (-not $d) { return }
    $numeroDisco = 0
    [int]::TryParse("$($d.DeviceId)", [ref]$numeroDisco) | Out-Null

    $lineas = New-Object System.Collections.Generic.List[string]
    $tipo = Clasificar-TipoAlmacenamiento -Disco $d
    $lineas.Add("Tipo: $tipo")
    $lineas.Add("Modelo: $($d.FriendlyName)")
    if ($d.Manufacturer) { $lineas.Add("Fabricante: $($d.Manufacturer)") }
    $lineas.Add("Numero de disco: $numeroDisco")
    if ($d.SerialNumber) { $lineas.Add("Numero de serie: $("$($d.SerialNumber)".Trim())") }
    $lineas.Add("Tamano: $([math]::Round($d.Size/1GB,2)) GB")
    $lineas.Add("Bus: $($d.BusType)")
    if ($d.MediaType) { $lineas.Add("Tipo de medio: $($d.MediaType)") }
    $lineas.Add("Estado de salud: $($d.HealthStatus)")
    $lineas.Add("Estado operativo: $($d.OperationalStatus)")

    $soloLectura = $false
    try {
        $discoWmi = Get-Disk -Number $numeroDisco -ErrorAction Stop
        $soloLectura = [bool]$discoWmi.IsReadOnly
        $lineas.Add("Solo lectura: $(if ($soloLectura) { 'SI' } else { 'No' })")
        $lineas.Add("Estilo de particion: $($discoWmi.PartitionStyle)")
    } catch {}

    try {
        $volumenes = @(Get-Partition -DiskNumber $numeroDisco -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
        if ($volumenes.Count -gt 0) {
            $lineas.Add("")
            $lineas.Add("Volumenes:")
            foreach ($p in $volumenes) {
                try {
                    $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
                    if ($vol) {
                        $libresGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
                        $totalGB = [math]::Round($vol.Size / 1GB, 1)
                        $lineas.Add(" - $($p.DriveLetter): $($vol.FileSystemLabel) [$($vol.FileSystem)] $libresGB GB libres de $totalGB GB")
                    }
                } catch {}
            }
        }
    } catch {}
    if ($txt) { $txt.Text = ($lineas -join "`r`n") }

    $firmware = "Desconocida"
    try {
        $unidad = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object { $_.Index -eq $numeroDisco } | Select-Object -First 1
        if ($unidad -and $unidad.FirmwareRevision) { $firmware = "$($unidad.FirmwareRevision)".Trim() }
    } catch {}
    if ($txtFw) {
        $fabricanteTxt = if ($d.Manufacturer) { "$($d.Manufacturer)" } else { "desconocido (se detectara por el nombre del modelo al buscar)" }
        $txtFw.Text = "Version de firmware actual: $firmware`r`nFabricante detectado: $fabricanteTxt"
    }
}

function Global:Accion-QuitarSoloLecturaAlmacenamiento {
    $d = Obtener-AlmacenamientoSeleccionado
    if (-not $d) { Show-Aviso "Primero detecta y selecciona un dispositivo de almacenamiento." "Sin seleccion"; return }
    if (-not (Requiere-Admin)) { return }
    $numeroDisco = 0
    [int]::TryParse("$($d.DeviceId)", [ref]$numeroDisco) | Out-Null
    $confirmar = Show-Confirm "Vas a quitar la proteccion de solo lectura del disco $numeroDisco ($($d.FriendlyName), serie: $("$($d.SerialNumber)".Trim())).`n`nAsegurate de que sea el dispositivo correcto: esta accion modifica sus atributos a nivel de sistema. Continuar?" "Confirmar quitar solo lectura"
    if (-not $confirmar) { return }
    Write-Log "Quitando proteccion de solo lectura del disco $numeroDisco..." -Tipo INFO
    try {
        $lineasScript = @("select disk $numeroDisco", "attributes disk clear readonly")
        $rutaScript = Join-Path $env:TEMP "dragon_quitar_solo_lectura.txt"
        Set-Content -Path $rutaScript -Value $lineasScript -Encoding ASCII -Force
        $salida = diskpart /s $rutaScript 2>&1 | Out-String
        Remove-Item $rutaScript -Force -ErrorAction SilentlyContinue

        $rutaPolitica = "HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies"
        try {
            if (Test-Path $rutaPolitica) {
                $valorActual = Get-ItemProperty -Path $rutaPolitica -Name "WriteProtect" -ErrorAction SilentlyContinue
                if ($valorActual -and $valorActual.WriteProtect -eq 1) {
                    Set-ItemProperty -Path $rutaPolitica -Name "WriteProtect" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    Write-Log "Politica de proteccion de escritura del sistema (registro) desactivada." -Tipo OK
                }
            }
        } catch {}

        Write-Log "diskpart: $($salida.Trim())" -Tipo INFO
        if ($salida -match '(?i)correctamente|successfully|se realizo|realizo correctamente') {
            Write-Log "Solo lectura quitado del disco $numeroDisco." -Tipo OK
            Show-Aviso "Listo. Se quito la proteccion de solo lectura del disco $numeroDisco.`n`nSi el dispositivo sigue en solo lectura, puede tener un interruptor fisico de bloqueo (comun en tarjetas SD/microSD con adaptador) que debes desactivar manualmente en el propio dispositivo." "Solo lectura quitado"
        } else {
            Write-Log "diskpart no confirmo el cambio en el disco $numeroDisco." -Tipo AVISO
            Show-Aviso "diskpart se ejecuto pero no confirmo el cambio. Revisa si el dispositivo tiene un interruptor fisico de bloqueo (comun en tarjetas SD/microSD) y que no este protegido por hardware." "Revisar dispositivo"
        }
        Detectar-AlmacenamientoModificacion
    } catch {
        Write-Log "Error al quitar solo lectura: $($_.Exception.Message)" -Tipo ERROR
        Show-Aviso "No se pudo quitar la proteccion de solo lectura: $($_.Exception.Message)" "Error"
    }
}

function Global:Accion-AnalizarErroresAlmacenamiento {
    $d = Obtener-AlmacenamientoSeleccionado
    if (-not $d) { Show-Aviso "Primero detecta y selecciona un dispositivo de almacenamiento." "Sin seleccion"; return }
    if (-not (Requiere-Admin)) { return }
    $txtR = $window.FindName("TxtModAlmacenamientoResultadoErrores")
    $numeroDisco = 0
    [int]::TryParse("$($d.DeviceId)", [ref]$numeroDisco) | Out-Null
    Write-Log "Analizando errores del disco $numeroDisco ($($d.FriendlyName))..." -Tipo INFO
    if ($txtR) { $txtR.Text = "Analizando, esto puede tardar unos minutos segun el tamano del disco..." }
    Wait-UI -Milisegundos 1
    $resultados = New-Object System.Collections.Generic.List[string]
    try {
        $volumenes = @(Get-Partition -DiskNumber $numeroDisco -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
        if ($volumenes.Count -eq 0) {
            $resultados.Add("El disco no tiene volumenes con letra de unidad asignada; no se puede analizar con chkdsk. Prueba con un disco que tenga al menos una particion visible en el Explorador de Windows.")
        } else {
            foreach ($p in $volumenes) {
                $letra = "$($p.DriveLetter):"
                try {
                    $reporte = Repair-Volume -DriveLetter $p.DriveLetter -Scan -ErrorAction Stop
                    $resultados.Add("$letra -> Analisis completado. Resultado: $reporte")
                } catch {
                    try {
                        $salida = cmd.exe /c "chkdsk $letra" 2>&1 | Out-String
                        $resultados.Add("$letra ->`r`n$($salida.Trim())")
                    } catch {
                        $resultados.Add("$letra -> No se pudo analizar: $($_.Exception.Message)")
                    }
                }
            }
        }
        Write-Log "Analisis de errores completado para el disco $numeroDisco." -Tipo OK
    } catch {
        $resultados.Add("Error durante el analisis: $($_.Exception.Message)")
        Write-Log "Error al analizar errores del disco $numeroDisco : $($_.Exception.Message)" -Tipo ERROR
    }
    if ($txtR) { $txtR.Text = ($resultados -join "`r`n`r`n") }
}

function Global:Accion-CorregirErroresAlmacenamiento {
    $d = Obtener-AlmacenamientoSeleccionado
    if (-not $d) { Show-Aviso "Primero detecta y selecciona un dispositivo de almacenamiento." "Sin seleccion"; return }
    if (-not (Requiere-Admin)) { return }
    $numeroDisco = 0
    [int]::TryParse("$($d.DeviceId)", [ref]$numeroDisco) | Out-Null
    $confirmar = Show-Confirm "Vas a corregir errores en el disco $numeroDisco ($($d.FriendlyName)).`n`nEsto puede tardar y, si el disco esta en uso por Windows, la reparacion se programara para el proximo reinicio. Continuar?" "Confirmar correccion de errores"
    if (-not $confirmar) { return }
    $txtR = $window.FindName("TxtModAlmacenamientoResultadoErrores")
    Write-Log "Corrigiendo errores del disco $numeroDisco ($($d.FriendlyName))..." -Tipo INFO
    if ($txtR) { $txtR.Text = "Corrigiendo errores, esto puede tardar..." }
    Wait-UI -Milisegundos 1
    $resultados = New-Object System.Collections.Generic.List[string]
    try {
        $volumenes = @(Get-Partition -DiskNumber $numeroDisco -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
        if ($volumenes.Count -eq 0) {
            $resultados.Add("El disco no tiene volumenes con letra de unidad asignada; no se puede corregir con chkdsk.")
        } else {
            foreach ($p in $volumenes) {
                $letra = "$($p.DriveLetter):"
                try {
                    $reporte = Repair-Volume -DriveLetter $p.DriveLetter -OfflineScanAndFix -ErrorAction Stop
                    $resultados.Add("$letra -> Correccion completada. Resultado: $reporte")
                    Write-Log "$letra corregido correctamente." -Tipo OK
                } catch {
                    try {
                        cmd.exe /c "echo Y | chkdsk $letra /f /r" | Out-Null
                        $resultados.Add("$letra -> El volumen esta en uso; la correccion se programo para el proximo reinicio del equipo.")
                        Write-Log "$letra : correccion programada para el proximo reinicio." -Tipo OK
                    } catch {
                        $resultados.Add("$letra -> No se pudo corregir: $($_.Exception.Message)")
                        Write-Log "No se pudo corregir $letra : $($_.Exception.Message)" -Tipo ERROR
                    }
                }
            }
        }
    } catch {
        $resultados.Add("Error durante la correccion: $($_.Exception.Message)")
        Write-Log "Error al corregir errores del disco $numeroDisco : $($_.Exception.Message)" -Tipo ERROR
    }
    if ($txtR) { $txtR.Text = ($resultados -join "`r`n`r`n") }
    Show-Aviso "Correccion finalizada. Revisa el panel de resultados para el detalle por volumen." "Correccion de errores"
}

function Global:Accion-BuscarFirmwareAlmacenamiento {
    $d = Obtener-AlmacenamientoSeleccionado
    if (-not $d) { Show-Aviso "Primero detecta y selecciona un dispositivo de almacenamiento." "Sin seleccion"; return }
    $texto = "$($d.Manufacturer) $($d.FriendlyName)"
    $combinado = "$($d.Manufacturer) $($d.FriendlyName)".ToLower()
    $url = $null
    $nombreHerramienta = $null
    if ($combinado -match 'samsung') { $url = 'https://semiconductor.samsung.com/consumer-storage/support/tools/'; $nombreHerramienta = 'Samsung Magician' }
    elseif ($combinado -match 'sandisk') { $url = 'https://www.sandisk.com/services-support/services/dashboard'; $nombreHerramienta = 'SanDisk SSD Dashboard' }
    elseif ($combinado -match 'western digital|wdc |wd blue|wd black|wd red|\bwd\b') { $url = 'https://support.wdc.com/downloads.aspx'; $nombreHerramienta = 'WD Dashboard' }
    elseif ($combinado -match 'crucial|micron') { $url = 'https://www.crucial.com/support/storage-executive'; $nombreHerramienta = 'Crucial Storage Executive' }
    elseif ($combinado -match 'kingston') { $url = 'https://www.kingston.com/en/support/technical/ssdmanager'; $nombreHerramienta = 'Kingston SSD Manager' }
    elseif ($combinado -match 'seagate') { $url = 'https://www.seagate.com/support/downloads/seatools/'; $nombreHerramienta = 'Seagate SeaTools' }
    elseif ($combinado -match 'toshiba') { $url = 'https://storage.toshiba.com/consumer-hdd/download-services'; $nombreHerramienta = 'Toshiba Storage' }
    elseif ($combinado -match 'adata') { $url = 'https://www.adata.com/en/consumer/software'; $nombreHerramienta = 'ADATA SSD Toolbox' }
    elseif ($combinado -match 'transcend') { $url = 'https://www.transcend-info.com/support/software'; $nombreHerramienta = 'Transcend Elite' }
    elseif ($combinado -match 'lexar') { $url = 'https://www.lexar.com/downloads/'; $nombreHerramienta = 'Lexar Downloads' }
    if ($url) {
        Write-Log "Abriendo la herramienta oficial ($nombreHerramienta) para buscar actualizacion de firmware..." -Tipo INFO
        Show-VentanaNavegador -Url $url -Titulo "Firmware - $nombreHerramienta" -TextoRespaldo "$texto firmware update download"
        Show-Aviso "Se abrio la pagina oficial de $nombreHerramienta. Descarga e instala su herramienta: ella identifica tu modelo exacto y te muestra si hay una actualizacion de firmware disponible para corregir errores.`n`nImportante: nunca instales firmware de un fabricante distinto al de tu dispositivo, puede dejarlo inutilizable de forma permanente." "Buscar firmware"
    } else {
        Write-Log "No se identifico el fabricante para buscar firmware automaticamente; se abre una busqueda general." -Tipo AVISO
        Show-VentanaNavegador -Url (Get-UrlRespaldoBusqueda -Texto "$texto firmware update download") -Titulo "Firmware" -TextoRespaldo "$texto firmware update download"
        Show-Aviso "No se pudo identificar automaticamente el fabricante exacto de este dispositivo. Se abrio una busqueda con su nombre: busca la herramienta oficial de su fabricante (por ejemplo Samsung Magician, WD Dashboard, Crucial Storage Executive, Kingston SSD Manager, Seagate SeaTools, segun corresponda) y usa unicamente firmware oficial de esa marca." "Firmware"
    }
}

function Accion-DiagnosticoCompletoEquipo {
    Write-DiagLog "========================================"
    Write-DiagLog "   DIAGNOSTICO COMPLETO DEL EQUIPO"
    Write-DiagLog "========================================"
    Accion-ProbarGraficaDiag
    Accion-VerDetallesPantalla
    Accion-ProbarAlmacenamiento
    Accion-ProbarVelocidadDisco
    Accion-ProbarVentiladores
    Accion-ProbarTemperaturaCPU
    Accion-ProbarBateria
    Accion-ProbarBluetooth
    Accion-ProbarPuertosUSB
    Accion-ProbarRed
    Accion-ProbarTiempoArranque
    Write-DiagLog "=== CONTROLADORES CON PROBLEMAS ==="
    try {
        $problemas = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' }
        if ($problemas) { foreach ($p in $problemas) { Write-DiagLog " - $($p.FriendlyName): $($p.Status)" } }
        else { Write-DiagLog "No se detectaron controladores con problemas." }
    } catch {}
    Write-DiagLog "Diagnostico automatico finalizado. Para camara, microfono, audio, teclado, mouse, pantalla y RAM usa los botones individuales (son pruebas interactivas)."
}

# ---------------------------------------------------------------------------
#  PERFILES RAPIDOS
# ---------------------------------------------------------------------------

function Set-ServicioSeguro {
    param([string]$Nombre, [string]$StartupType, [switch]$Detener)
    $svc = Get-Service -Name $Nombre -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    try {
        if ($Detener) { Stop-Service -Name $Nombre -Force -ErrorAction SilentlyContinue }
        Set-Service -Name $Nombre -StartupType $StartupType -ErrorAction Stop
        Write-Log "Servicio '$Nombre' -> $StartupType" -Tipo OK
    } catch {
        Write-Log "No se pudo ajustar el servicio '$Nombre'." -Tipo AVISO
    }
}

# Servicios de telemetria/bloat comunes, seguros de tocar en casi cualquier equipo
$Script:ServiciosBloatComun = @(
    'DiagTrack', 'dmwappushservice', 'MapsBroker', 'lfsvc',
    'RetailDemo', 'WMPNetworkSvc', 'RemoteRegistry', 'WalletService', 'PhoneSvc'
)

# --- Reducir cantidad de procesos y subprocesos (para equipos de bajo consumo) ---

function Accion-AgruparServiciosSvcHost {
    # Por defecto, en equipos con mas de ~3.5 GB de RAM, Windows le da a CADA
    # servicio su propio proceso svchost.exe independiente (mas aislamiento,
    # pero muchos mas procesos y subprocesos consumiendo CPU y RAM). Al subir
    # este umbral, forzamos a Windows a agrupar varios servicios dentro del
    # mismo proceso, reduciendo la cantidad total de procesos en ejecucion.
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Value 0x0F000000 -Type DWord
        Write-Log "Windows agrupara mas servicios por proceso (menos procesos svchost.exe y subprocesos activos). Requiere reiniciar." -Tipo OK
    } catch {
        Write-Log "No se pudo ajustar el agrupamiento de servicios de Windows." -Tipo AVISO
    }
}
function Accion-AgruparServiciosSvcHostRestaurar {
    try {
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -ErrorAction SilentlyContinue
    } catch {}
}

# Aplicaciones comunes que suelen quedarse corriendo en segundo plano sin ser
# esenciales para trabajar; cada una son varios procesos/subprocesos que
# consumen CPU en un equipo de pocos recursos si no se estan usando activamente.
$Script:ProcesosNoEsenciales = @(
    'Spotify','Discord','Skype','Teams','ms-teams','OneDrive','YourPhone','PhoneExperienceHost',
    'GameBar','GameBarFTServer','EpicGamesLauncher','EpicWebHelper','Steam','SteamService',
    'iCloudServices','iCloudDrive','Dropbox','CCleaner','Adobe Desktop Service','AdobeUpdateService',
    'OneDriveSetup','SearchIndexer'
)

function Accion-CerrarProcesosNoEsenciales {
    $cerrados = 0
    foreach ($nombre in $Script:ProcesosNoEsenciales) {
        $procs = Get-Process -Name $nombre -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                Write-Log "Proceso en segundo plano cerrado: $($p.ProcessName) (PID $($p.Id))" -Tipo OK
                $cerrados++
            } catch {}
        }
    }
    if ($cerrados -eq 0) {
        Write-Log "No se encontraron procesos de aplicaciones no esenciales en ejecucion." -Tipo INFO
    } else {
        Write-Log "$cerrados proceso(s) en segundo plano cerrado(s), liberando CPU y subprocesos." -Tipo OK
    }
}

# --- Acciones individuales reutilizables (perfiles + modo manual) ---

function Accion-EfectosVisualesSilencioso {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "VisualFXSetting" -Value 2 -Type DWord
        Write-Log "Efectos visuales ajustados a 'mejor rendimiento'." -Tipo OK
    } catch { Write-Log "No se pudo ajustar los efectos visuales." -Tipo AVISO }
}

function Accion-TransparenciaOff {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "EnableTransparency" -Value 0 -Type DWord
        Write-Log "Transparencia de Windows desactivada (menos uso de GPU/CPU)." -Tipo OK
    } catch { Write-Log "No se pudo desactivar la transparencia." -Tipo AVISO }
}
function Accion-TransparenciaOn {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (Test-Path $path) { Set-ItemProperty -Path $path -Name "EnableTransparency" -Value 1 -Type DWord -ErrorAction SilentlyContinue }
    } catch {}
}

function Accion-TransparenciaYEfectosOff { Accion-TransparenciaOff; Accion-EfectosVisualesSilencioso }

function Accion-BackgroundAppsOff {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "GlobalUserDisabled" -Value 1 -Type DWord
        Write-Log "Apps en segundo plano desactivadas (menos uso de RAM y CPU en reposo)." -Tipo OK
    } catch { Write-Log "No se pudo desactivar las apps en segundo plano." -Tipo AVISO }
}
function Accion-BackgroundAppsOn {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        if (Test-Path $path) { Set-ItemProperty -Path $path -Name "GlobalUserDisabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue }
    } catch {}
}

function Accion-SugerenciasOff {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        foreach ($n in @('SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled')) {
            Set-ItemProperty -Path $path -Name $n -Value 0 -Type DWord -ErrorAction SilentlyContinue
        }
        Write-Log "Sugerencias y anuncios de Windows desactivados." -Tipo OK
    } catch { Write-Log "No se pudo desactivar las sugerencias de Windows." -Tipo AVISO }
}
function Accion-SugerenciasOn {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (Test-Path $path) {
            foreach ($n in @('SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled')) {
                Set-ItemProperty -Path $path -Name $n -Value 1 -Type DWord -ErrorAction SilentlyContinue
            }
        }
    } catch {}
}

function Accion-OneDriveStartupOff {
    try {
        Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
        Write-Log "Inicio automatico de OneDrive desactivado (menos RAM y disco en segundo plano)." -Tipo OK
    } catch { Write-Log "No se pudo desactivar el inicio de OneDrive." -Tipo AVISO }
}

function Accion-PriorizarPrimerPlano {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord
        Write-Log "CPU priorizado para las aplicaciones en primer plano (mas respuesta, menos 'lag')." -Tipo OK
    } catch { Write-Log "No se pudo ajustar la prioridad de CPU." -Tipo AVISO }
}
function Accion-PriorizarPrimerPlanoRestaurar {
    try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -ErrorAction SilentlyContinue } catch {}
}

function Accion-HibernacionOff {
    if (-not (Requiere-Admin)) { return }
    try {
        powercfg /hibernate off
        Write-Log "Hibernacion desactivada: libera espacio en disco (igual al tamaño de tu RAM) y evita escrituras periodicas." -Tipo OK
    } catch { Write-Log "No se pudo desactivar la hibernacion." -Tipo AVISO }
}
function Accion-HibernacionOn {
    try { powercfg /hibernate on; Write-Log "Hibernacion reactivada." -Tipo OK } catch { Write-Log "No se pudo reactivar la hibernacion." -Tipo AVISO }
}

function Accion-RestaurarSistemaLimitar {
    if (-not (Requiere-Admin)) { return }
    try {
        cmd.exe /c "vssadmin resize shadowstorage /for=C: /on=C: /maxsize=3%" | Out-Null
        Write-Log "Espacio reservado para Restaurar sistema limitado al 3% del disco (menos carga de disco en segundo plano)." -Tipo OK
    } catch { Write-Log "No se pudo limitar el espacio de Restaurar sistema." -Tipo AVISO }
}

function Accion-DeliveryOptimizationOff {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ServicioSeguro -Nombre 'DoSvc' -StartupType Manual -Detener
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "DODownloadMode" -Value 0 -Type DWord
        Write-Log "Delivery Optimization desactivado (evita descargas/subidas P2P en segundo plano que usan disco y red)." -Tipo OK
    } catch { Write-Log "No se pudo desactivar Delivery Optimization." -Tipo AVISO }
}
function Accion-DeliveryOptimizationOn {
    try {
        Set-Service -Name 'DoSvc' -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name 'DoSvc' -ErrorAction SilentlyContinue
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "DODownloadMode" -ErrorAction SilentlyContinue }
    } catch {}
}

$Script:TareasDiagnostico = @(
    @{Path='\Microsoft\Windows\Application Experience\'; Name='Microsoft Compatibility Appraiser'},
    @{Path='\Microsoft\Windows\Application Experience\'; Name='ProgramDataUpdater'},
    @{Path='\Microsoft\Windows\Autochk\'; Name='Proxy'},
    @{Path='\Microsoft\Windows\Customer Experience Improvement Program\'; Name='Consolidator'},
    @{Path='\Microsoft\Windows\Customer Experience Improvement Program\'; Name='UsbCeip'},
    @{Path='\Microsoft\Windows\DiskDiagnostic\'; Name='Microsoft-Windows-DiskDiagnosticDataCollector'},
    @{Path='\Microsoft\Windows\Maintenance\'; Name='WinSAT'},
    @{Path='\Microsoft\Windows\Windows Error Reporting\'; Name='QueueReporting'}
)

function Accion-TareasDiagnosticoOff {
    if (-not (Requiere-Admin)) { return }
    foreach ($t in $Script:TareasDiagnostico) {
        try {
            Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
            Write-Log "Tarea programada desactivada: $($t.Name)" -Tipo OK
        } catch {}
    }
}
function Accion-TareasDiagnosticoOn {
    foreach ($t in $Script:TareasDiagnostico) {
        try { Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null } catch {}
    }
}

# ---------------------------------------------------------------------------
#  PERFILES RAPIDOS (reforzados: CPU, RAM y disco)
# ---------------------------------------------------------------------------

function Perfil-BajoConsumo {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Perfil para equipos con pocos recursos (Celeron, Core i3, Core 2 Duo, poca RAM o disco lento).`n`nSe desactivaran servicios en segundo plano, SysMain y la indexacion de busqueda, apps en segundo plano, sugerencias de Windows, transparencia, hibernacion, Delivery Optimization y tareas de diagnostico; se agruparan mas servicios de Windows en menos procesos, se cerraran apps no esenciales que esten corriendo, se limpiaran archivos temporales/papelera, y se priorizara la CPU para las apps abiertas (menos procesos y subprocesos = menos carga de CPU).`n`n¿Aplicar perfil de Bajo consumo?")) { return }

    $prog = New-VentanaProgreso -Titulo "Aplicando perfil: Equipo de bajo consumo"
    $pasos = @(
        @{ Pct=7; Txt="Desactivando servicios de telemetria y funciones poco usadas..."; Accion={ foreach ($s in $Script:ServiciosBloatComun) { Set-ServicioSeguro -Nombre $s -StartupType Disabled -Detener } } }
        @{ Pct=15; Txt="Desactivando SysMain, indexacion, panel tactil, fax y Xbox..."; Accion={
            Set-ServicioSeguro -Nombre 'SysMain' -StartupType Disabled -Detener
            Set-ServicioSeguro -Nombre 'WSearch' -StartupType Disabled -Detener
            Set-ServicioSeguro -Nombre 'TabletInputService' -StartupType Disabled -Detener
            Set-ServicioSeguro -Nombre 'Fax' -StartupType Disabled -Detener
            foreach ($s in @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')) { Set-ServicioSeguro -Nombre $s -StartupType Disabled -Detener }
        } }
        @{ Pct=25; Txt="Ajustando transparencia y efectos visuales..."; Accion={ Accion-TransparenciaYEfectosOff } }
        @{ Pct=32; Txt="Desactivando apps en segundo plano..."; Accion={ Accion-BackgroundAppsOff } }
        @{ Pct=39; Txt="Desactivando sugerencias de Windows..."; Accion={ Accion-SugerenciasOff } }
        @{ Pct=46; Txt="Desactivando inicio automatico de OneDrive..."; Accion={ Accion-OneDriveStartupOff } }
        @{ Pct=53; Txt="Desactivando hibernacion (libera espacio en disco)..."; Accion={ Accion-HibernacionOff } }
        @{ Pct=60; Txt="Limitando espacio de Restaurar sistema..."; Accion={ Accion-RestaurarSistemaLimitar } }
        @{ Pct=67; Txt="Desactivando Delivery Optimization y tareas de diagnostico..."; Accion={ Accion-DeliveryOptimizationOff; Accion-TareasDiagnosticoOff } }
        @{ Pct=75; Txt="Agrupando servicios de Windows para reducir procesos en ejecucion..."; Accion={ Accion-AgruparServiciosSvcHost } }
        @{ Pct=82; Txt="Cerrando aplicaciones no esenciales en segundo plano..."; Accion={ Accion-CerrarProcesosNoEsenciales } }
        @{ Pct=90; Txt="Limpiando archivos temporales y papelera de reciclaje..."; Accion={ Accion-LimpiarTemporales; Accion-VaciarPapelera } }
        @{ Pct=97; Txt="Priorizando CPU para aplicaciones en primer plano..."; Accion={ Accion-PriorizarPrimerPlano } }
    )
    foreach ($p in $pasos) {
        Update-VentanaProgreso -Ventana $prog -Porcentaje $p.Pct -Estado $p.Txt -LogLinea $p.Txt
        & $p.Accion
    }
    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Perfil de Bajo consumo aplicado."
    Write-Log "Perfil de Bajo consumo aplicado. Se recomienda reiniciar el equipo." -Tipo OK
    Show-Aviso "Perfil de Bajo consumo aplicado.`nReinicia el equipo para que todos los cambios (menos procesos/subprocesos activos, CPU, RAM y disco) surtan efecto completo." "Perfil aplicado"
}

function Perfil-EquipoModerno {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Perfil para equipos con buen hardware (SSD/NVMe, 8GB+ RAM).`n`nSe desactivaran servicios de telemetria y funciones poco usadas (mapas, fax, Xbox, etc.), sugerencias de Windows y Delivery Optimization, manteniendo la busqueda y el precargado activados; se activara Storage Sense e Inicio rapido, se limpiaran temporales, y el plan de energia quedara en Equilibrado.`n`n¿Aplicar perfil de Equipo moderno?")) { return }

    $prog = New-VentanaProgreso -Titulo "Aplicando perfil: Equipo moderno"
    Update-VentanaProgreso -Ventana $prog -Porcentaje 12 -Estado "Desactivando servicios de telemetria..." -LogLinea "Ajustando servicios de telemetria a Manual."
    foreach ($s in $Script:ServiciosBloatComun) { Set-ServicioSeguro -Nombre $s -StartupType Manual -Detener }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 28 -Estado "Desactivando servicios de Xbox..." -LogLinea "Ajustando servicios de Xbox a Manual."
    foreach ($s in @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')) { Set-ServicioSeguro -Nombre $s -StartupType Manual -Detener }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 45 -Estado "Desactivando sugerencias de Windows y Delivery Optimization..." -LogLinea "Aplicando ajustes de sugerencias y Delivery Optimization."
    Accion-SugerenciasOff
    Accion-DeliveryOptimizationOff

    Update-VentanaProgreso -Ventana $prog -Porcentaje 58 -Estado "Activando Storage Sense (limpieza automatica)..." -LogLinea "Storage Sense activado."
    try {
        $pathStorage = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
        if (-not (Test-Path $pathStorage)) { New-Item -Path $pathStorage -Force | Out-Null }
        Set-ItemProperty -Path $pathStorage -Name "01" -Value 1 -Type DWord
        Set-ItemProperty -Path $pathStorage -Name "04" -Value 1 -Type DWord
    } catch { Write-Log "No se pudo activar Storage Sense." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 70 -Estado "Activando Inicio rapido (Fast Startup)..."
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 1 -Type DWord
        Write-Log "Inicio rapido (Fast Startup) activado." -Tipo OK
        Update-VentanaProgreso -Ventana $prog -Porcentaje 70 -Estado "Inicio rapido activado" -LogLinea "Inicio rapido (Fast Startup) activado."
    } catch { Write-Log "No se pudo activar el Inicio rapido." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 82 -Estado "Limpiando archivos temporales..." -LogLinea "Limpiando archivos temporales."
    Accion-LimpiarTemporales

    Update-VentanaProgreso -Ventana $prog -Porcentaje 92 -Estado "Ajustando plan de energia..." -LogLinea "Estableciendo plan de energia Equilibrado."
    try {
        powercfg -setactive SCHEME_BALANCED
        Write-Log "Plan de energia establecido en Equilibrado." -Tipo OK
    } catch { Write-Log "No se pudo cambiar el plan de energia." -Tipo AVISO }

    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Perfil de Equipo moderno aplicado."
    Write-Log "Perfil de Equipo moderno aplicado. Se recomienda reiniciar el equipo." -Tipo OK
    Show-Aviso "Perfil de Equipo moderno aplicado.`nReinicia el equipo para que todos los cambios surtan efecto." "Perfil aplicado"
}

function Perfil-Gamer {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Perfil para mejorar el rendimiento en juegos.`n`nAlto rendimiento, Modo juego, GPU acelerada por hardware, perfil de baja latencia (prioridad de tareas en tiempo real), sin limite de red para multimedia, SysMain/indexacion desactivados, Delivery Optimization desactivado, apps no esenciales cerradas (Discord, Spotify, etc.) y CPU priorizado para primer plano (los servicios de Xbox se mantienen activos).`n`n¿Aplicar perfil Gamer?")) { return }

    $prog = New-VentanaProgreso -Titulo "Aplicando perfil: Equipo gamer"

    Update-VentanaProgreso -Ventana $prog -Porcentaje 8 -Estado "Desactivando servicios de telemetria..." -LogLinea "Ajustando servicios de telemetria a Manual."
    foreach ($s in $Script:ServiciosBloatComun) { Set-ServicioSeguro -Nombre $s -StartupType Manual -Detener }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 17 -Estado "Desactivando SysMain, indexacion y panel tactil..." -LogLinea "SysMain, WSearch y TabletInputService ajustados."
    Set-ServicioSeguro -Nombre 'SysMain' -StartupType Disabled -Detener
    Set-ServicioSeguro -Nombre 'WSearch' -StartupType Manual -Detener
    Set-ServicioSeguro -Nombre 'TabletInputService' -StartupType Manual -Detener

    Update-VentanaProgreso -Ventana $prog -Porcentaje 27 -Estado "Desactivando Delivery Optimization..." -LogLinea "Delivery Optimization desactivado."
    Accion-DeliveryOptimizationOff

    Update-VentanaProgreso -Ventana $prog -Porcentaje 36 -Estado "Cerrando aplicaciones no esenciales en segundo plano..." -LogLinea "Cerrando apps no esenciales para liberar recursos."
    Accion-CerrarProcesosNoEsenciales

    Update-VentanaProgreso -Ventana $prog -Porcentaje 45 -Estado "Priorizando CPU para primer plano..." -LogLinea "CPU priorizada para primer plano."
    Accion-PriorizarPrimerPlano

    Update-VentanaProgreso -Ventana $prog -Porcentaje 55 -Estado "Aplicando perfil de baja latencia (prioridad en tiempo real)..." -LogLinea "SystemResponsiveness y prioridad de tareas 'Games' ajustadas."
    Aplicar-BajaLatenciaCore

    Update-VentanaProgreso -Ventana $prog -Porcentaje 66 -Estado "Estableciendo plan de energia de Alto rendimiento..."
    try {
        powercfg -setactive SCHEME_MIN
        Write-Log "Plan de energia establecido en Alto rendimiento." -Tipo OK
        Update-VentanaProgreso -Ventana $prog -Porcentaje 66 -Estado "Estableciendo plan de energia de Alto rendimiento..." -LogLinea "Plan de energia: Alto rendimiento."
    } catch { Write-Log "No se pudo cambiar el plan de energia." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 76 -Estado "Activando Modo juego de Windows..."
    try {
        $pathGameBar = "HKCU:\Software\Microsoft\GameBar"
        if (-not (Test-Path $pathGameBar)) { New-Item -Path $pathGameBar -Force | Out-Null }
        Set-ItemProperty -Path $pathGameBar -Name "AllowAutoGameMode" -Value 1 -Type DWord
        Set-ItemProperty -Path $pathGameBar -Name "AutoGameModeEnabled" -Value 1 -Type DWord
        Write-Log "Modo juego de Windows activado." -Tipo OK
        Update-VentanaProgreso -Ventana $prog -Porcentaje 76 -Estado "Modo juego activado" -LogLinea "Modo juego de Windows activado."
    } catch { Write-Log "No se pudo activar el Modo juego." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 85 -Estado "Desactivando grabacion en segundo plano de Game Bar..."
    try {
        $pathDVR = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $pathDVR)) { New-Item -Path $pathDVR -Force | Out-Null }
        Set-ItemProperty -Path $pathDVR -Name "GameDVR_Enabled" -Value 0 -Type DWord
        Write-Log "Grabacion en segundo plano de Xbox Game Bar desactivada." -Tipo OK
        Update-VentanaProgreso -Ventana $prog -Porcentaje 85 -Estado "Game DVR desactivado" -LogLinea "Grabacion en segundo plano desactivada."
    } catch { Write-Log "No se pudo desactivar la grabacion de Game Bar." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 90 -Estado "Verificando GPU acelerada por hardware..."
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord
        Update-VentanaProgreso -Ventana $prog -Porcentaje 90 -Estado "GPU acelerada activada" -LogLinea "Programacion de GPU por hardware activada."
    } catch { Write-Log "Tu equipo/drivers pueden no soportar la programacion de GPU por hardware." -Tipo AVISO }

    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Perfil Gamer aplicado."
    Write-Log "Perfil Gamer aplicado. Se recomienda reiniciar el equipo." -Tipo OK
    Show-Aviso "Perfil Gamer aplicado.`nReinicia el equipo para que todos los cambios (especialmente el de GPU y baja latencia) surtan efecto." "Perfil aplicado"
}

function Perfil-Restaurar {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto revertira los cambios de los perfiles rapidos y del modo manual: servicios a Automatico/Manual, plan de energia a Equilibrado, efectos visuales, transparencia, apps en segundo plano, sugerencias, hibernacion, Delivery Optimization y prioridad de CPU a sus valores por defecto.`n`n¿Restaurar configuracion predeterminada?")) { return }

    $prog = New-VentanaProgreso -Titulo "Restaurando configuracion predeterminada"

    $todos = $Script:ServiciosBloatComun + @('SysMain','WSearch','TabletInputService','Fax','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')
    Update-VentanaProgreso -Ventana $prog -Porcentaje 10 -Estado "Restaurando servicios a Manual/Iniciado..."
    $i = 0
    foreach ($s in $todos) {
        $i++
        $pct = 10 + [math]::Round(($i / $todos.Count) * 40)
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            try {
                Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
                Start-Service -Name $s -ErrorAction SilentlyContinue
                Write-Log "Servicio '$s' restaurado a Manual/Iniciado." -Tipo OK
                Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Restaurando servicios..." -LogLinea "Servicio '$s' restaurado."
            } catch {}
        }
    }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 55 -Estado "Restaurando plan de energia y efectos visuales..."
    try { powercfg -setactive SCHEME_BALANCED; Write-Log "Plan de energia restaurado a Equilibrado." -Tipo OK } catch {}
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (Test-Path $path) { Set-ItemProperty -Path $path -Name "VisualFXSetting" -Value 0 -Type DWord }
    } catch {}

    Update-VentanaProgreso -Ventana $prog -Porcentaje 70 -Estado "Restaurando transparencia, apps en segundo plano y sugerencias..." -LogLinea "Restaurando ajustes visuales y de apps."
    Accion-TransparenciaOn
    Accion-BackgroundAppsOn
    Accion-SugerenciasOn

    Update-VentanaProgreso -Ventana $prog -Porcentaje 85 -Estado "Restaurando hibernacion, Delivery Optimization y tareas..." -LogLinea "Restaurando hibernacion y tareas de diagnostico."
    Accion-HibernacionOn
    Accion-DeliveryOptimizationOn
    Accion-TareasDiagnosticoOn
    Accion-PriorizarPrimerPlanoRestaurar
    Accion-AgruparServiciosSvcHostRestaurar

    Update-VentanaProgreso -Ventana $prog -Porcentaje 95 -Estado "Restaurando ajustes de GPU y red..." -LogLinea "Restaurando GPU y red multimedia a valores por defecto."
    try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 0 -Type DWord -ErrorAction SilentlyContinue } catch {}
    try { Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -ErrorAction SilentlyContinue } catch {}
    try { Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 20 -Type DWord -ErrorAction SilentlyContinue } catch {}
    try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue } catch {}

    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Configuracion predeterminada restaurada."
    Write-Log "Configuracion predeterminada restaurada. Se recomienda reiniciar el equipo." -Tipo OK
    Show-Aviso "Configuracion predeterminada restaurada.`nReinicia el equipo para completar los cambios." "Restauracion completa"
}

# ---------------------------------------------------------------------------
#  MODO MANUAL: checklist de servicios y ajustes (CPU / RAM / disco)
# ---------------------------------------------------------------------------

$Script:ChecklistManual = @(
    @{ Categoria='CPU'; Nombre='Priorizar aplicaciones en primer plano (mejor respuesta de CPU)'; Tipo='Accion'; ValorOn='Accion-PriorizarPrimerPlano' },
    @{ Categoria='CPU'; Nombre='Desactivar transparencia y efectos visuales (menos uso de CPU/GPU)'; Tipo='Accion'; ValorOn='Accion-TransparenciaYEfectosOff' },
    @{ Categoria='CPU'; Nombre='Agrupar servicios de Windows en menos procesos (menos subprocesos activos)'; Tipo='Accion'; ValorOn='Accion-AgruparServiciosSvcHost' },
    @{ Categoria='CPU'; Nombre='Cerrar apps no esenciales en segundo plano (Spotify, Discord, Steam, etc.)'; Tipo='Accion'; ValorOn='Accion-CerrarProcesosNoEsenciales' },
    @{ Categoria='Memoria RAM'; Nombre='Desactivar SysMain / Superfetch'; Tipo='Servicio'; Valor='SysMain' },
    @{ Categoria='Memoria RAM'; Nombre='Desactivar apps en segundo plano'; Tipo='Accion'; ValorOn='Accion-BackgroundAppsOff' },
    @{ Categoria='Memoria RAM'; Nombre='Desactivar inicio automatico de OneDrive'; Tipo='Accion'; ValorOn='Accion-OneDriveStartupOff' },
    @{ Categoria='Memoria RAM'; Nombre='Desactivar sugerencias y anuncios de Windows'; Tipo='Accion'; ValorOn='Accion-SugerenciasOff' },
    @{ Categoria='Disco duro (recomendado en Celeron / i3 / Core 2 Duo)'; Nombre='Desactivar indexacion de busqueda (WSearch)'; Tipo='Servicio'; Valor='WSearch' },
    @{ Categoria='Disco duro (recomendado en Celeron / i3 / Core 2 Duo)'; Nombre='Desactivar hibernacion (libera espacio en disco)'; Tipo='Accion'; ValorOn='Accion-HibernacionOff' },
    @{ Categoria='Disco duro (recomendado en Celeron / i3 / Core 2 Duo)'; Nombre='Limitar Restaurar sistema al 3% del disco'; Tipo='Accion'; ValorOn='Accion-RestaurarSistemaLimitar' },
    @{ Categoria='Disco duro (recomendado en Celeron / i3 / Core 2 Duo)'; Nombre='Desactivar Delivery Optimization (descargas P2P)'; Tipo='Accion'; ValorOn='Accion-DeliveryOptimizationOff' },
    @{ Categoria='Disco duro (recomendado en Celeron / i3 / Core 2 Duo)'; Nombre='Desactivar tareas programadas de diagnostico/CEIP'; Tipo='Accion'; ValorOn='Accion-TareasDiagnosticoOff' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Telemetria (DiagTrack)'; Tipo='Servicio'; Valor='DiagTrack' },
    @{ Categoria='Servicios en segundo plano'; Nombre='WAP Push (dmwappushservice)'; Tipo='Servicio'; Valor='dmwappushservice' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Mapas descargados (MapsBroker)'; Tipo='Servicio'; Valor='MapsBroker' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Geolocalizacion (lfsvc)'; Tipo='Servicio'; Valor='lfsvc' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Modo demo de tienda (RetailDemo)'; Tipo='Servicio'; Valor='RetailDemo' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Compartir Windows Media Player (WMPNetworkSvc)'; Tipo='Servicio'; Valor='WMPNetworkSvc' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Registro remoto (RemoteRegistry)'; Tipo='Servicio'; Valor='RemoteRegistry' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Billetera de Windows (WalletService)'; Tipo='Servicio'; Valor='WalletService' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Servicio de telefono (PhoneSvc)'; Tipo='Servicio'; Valor='PhoneSvc' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Panel tactil (TabletInputService)'; Tipo='Servicio'; Valor='TabletInputService' },
    @{ Categoria='Servicios en segundo plano'; Nombre='Fax'; Tipo='Servicio'; Valor='Fax' },
    @{ Categoria='Servicios de Xbox (si no usas Xbox/Game Pass)'; Nombre='Xbox Auth Manager'; Tipo='Servicio'; Valor='XblAuthManager' },
    @{ Categoria='Servicios de Xbox (si no usas Xbox/Game Pass)'; Nombre='Xbox Game Save'; Tipo='Servicio'; Valor='XblGameSave' },
    @{ Categoria='Servicios de Xbox (si no usas Xbox/Game Pass)'; Nombre='Xbox Live Networking'; Tipo='Servicio'; Valor='XboxNetApiSvc' }
)

function Show-VentanaManual {
    [xml]$xamlManual = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Optimizacion manual - Adrian Barrientos" Height="640" Width="580"
        WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)</Window.Resources>
  <DockPanel Margin="14">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Text="Selecciona los ajustes que quieras aplicar. Recomendado especialmente para equipos con Celeron, Core i3 o Core 2 Duo." Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnAplicarManual" Content="Aplicar seleccionados" Width="170" Margin="0,0,8,0"/>
      <Button x:Name="BtnCerrarManual" Content="Cerrar" Width="100"/>
    </StackPanel>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="PanelChecklist"/>
    </ScrollViewer>
  </DockPanel>
</Window>
"@
    $readerM = New-Object System.Xml.XmlNodeReader $xamlManual
    $winM = [Windows.Markup.XamlReader]::Load($readerM)
    Iniciar-EfectosNeon -Ventana $winM
    $panel = $winM.FindName("PanelChecklist")

    $checkboxes = New-Object System.Collections.Generic.List[object]
    $categorias = $Script:ChecklistManual | ForEach-Object { $_.Categoria } | Select-Object -Unique
    foreach ($cat in $categorias) {
        $gb = New-Object System.Windows.Controls.GroupBox
        $gb.Header = $cat
        $gb.Foreground = [System.Windows.Media.Brushes]::White
        $gb.Margin = "0,0,0,10"
        $sp = New-Object System.Windows.Controls.StackPanel
        foreach ($item in ($Script:ChecklistManual | Where-Object { $_.Categoria -eq $cat })) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $item.Nombre
            $cb.Foreground = [System.Windows.Media.Brushes]::White
            $cb.Margin = "4"
            $cb.Tag = $item
            $sp.Children.Add($cb) | Out-Null
            $checkboxes.Add($cb) | Out-Null
        }
        $gb.Content = $sp
        $panel.Children.Add($gb) | Out-Null
    }

    $winM.FindName("BtnCerrarManual").Add_Click({ $winM.Close() })
    $winM.FindName("BtnAplicarManual").Add_Click({
        if (-not (Requiere-Admin)) { return }
        $seleccionados = @($checkboxes | Where-Object { $_.IsChecked -eq $true })
        if ($seleccionados.Count -eq 0) { Show-Aviso "No has seleccionado ningun ajuste." "Nada seleccionado"; return }
        if (-not (Show-Confirm "Se aplicaran $($seleccionados.Count) ajuste(s) seleccionados. ¿Continuar?")) { return }

        $prog = New-VentanaProgreso -Titulo "Aplicando ajustes manuales"
        $i = 0
        foreach ($cb in $seleccionados) {
            $i++
            $pct = [math]::Round(($i / $seleccionados.Count) * 100)
            $item = $cb.Tag
            Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Aplicando: $($item.Nombre)" -LogLinea "Aplicando: $($item.Nombre)"
            if ($item.Tipo -eq 'Servicio') {
                Set-ServicioSeguro -Nombre $item.Valor -StartupType Disabled -Detener
            } elseif ($item.Tipo -eq 'Accion') {
                try { & $item.ValorOn } catch { Write-Log "No se pudo aplicar: $($item.Nombre)" -Tipo AVISO }
            }
        }
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Ajustes manuales aplicados."
        Write-Log "Ajustes manuales aplicados: $($seleccionados.Count)." -Tipo OK
        Show-Aviso "Ajustes aplicados.`nSe recomienda reiniciar el equipo." "Listo"
    })

    $winM.ShowDialog() | Out-Null
}

# ---------------------------------------------------------------------------
#  REGISTRO DE WINDOWS: edicion y analisis/reparacion de errores
# ---------------------------------------------------------------------------

# --- Ediciones individuales del registro ---

function Accion-MostrarExtensionesOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Extensiones de archivo visibles activadas." -Tipo OK
    } catch { Write-Log "No se pudo activar la visualizacion de extensiones." -Tipo AVISO }
}
function Accion-MostrarExtensionesOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Extensiones de archivo ocultas (comportamiento por defecto)." -Tipo OK
    } catch { Write-Log "No se pudo ocultar las extensiones." -Tipo AVISO }
}
function Accion-MostrarOcultosOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Archivos y carpetas ocultos visibles." -Tipo OK
    } catch { Write-Log "No se pudo mostrar los archivos ocultos." -Tipo AVISO }
}
function Accion-MostrarOcultosOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 2 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Archivos y carpetas ocultos ya no se muestran." -Tipo OK
    } catch { Write-Log "No se pudo ocultar los archivos." -Tipo AVISO }
}
function Accion-RecientesOff {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $path -Name "Start_TrackDocs" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        $path2 = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
        if (-not (Test-Path $path2)) { New-Item -Path $path2 -Force | Out-Null }
        Set-ItemProperty -Path $path2 -Name "ShowFrequent" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path2 -Name "ShowRecent" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Restart-ExplorerSilencioso
        Write-Log "Archivos y carpetas recientes desactivados en Acceso rapido." -Tipo OK
    } catch { Write-Log "No se pudo desactivar los elementos recientes." -Tipo AVISO }
}
function Accion-RecientesOn {
    try {
        $path2 = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
        Set-ItemProperty -Path $path2 -Name "ShowFrequent" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path2 -Name "ShowRecent" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Restart-ExplorerSilencioso
        Write-Log "Archivos y carpetas recientes reactivados en Acceso rapido." -Tipo OK
    } catch { Write-Log "No se pudo reactivar los elementos recientes." -Tipo AVISO }
}
function Accion-TelemetriaMinima {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "AllowTelemetry" -Value 0 -Type DWord
        Write-Log "Telemetria de Windows reducida al minimo." -Tipo OK
    } catch { Write-Log "No se pudo reducir la telemetria (algunas ediciones de Windows no lo permiten)." -Tipo AVISO }
}
function Accion-TelemetriaRestaurar {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "AllowTelemetry" -ErrorAction SilentlyContinue }
    } catch {}
}
function Accion-AdvertisingIdOff {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "Enabled" -Value 0 -Type DWord
        Write-Log "ID de publicidad (anuncios personalizados) desactivado." -Tipo OK
    } catch { Write-Log "No se pudo desactivar el ID de publicidad." -Tipo AVISO }
}
function Accion-AdvertisingIdOn {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        if (Test-Path $path) { Set-ItemProperty -Path $path -Name "Enabled" -Value 1 -Type DWord -ErrorAction SilentlyContinue }
    } catch {}
}
function Accion-CortanaOff {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "AllowCortana" -Value 0 -Type DWord
        Write-Log "Cortana desactivada." -Tipo OK
    } catch { Write-Log "No se pudo desactivar Cortana." -Tipo AVISO }
}
function Accion-CortanaOn {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "AllowCortana" -ErrorAction SilentlyContinue }
    } catch {}
}
function Accion-FastStartupOn {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 1 -Type DWord
        Write-Log "Inicio rapido (Fast Startup) activado." -Tipo OK
    } catch { Write-Log "No se pudo activar el Inicio rapido." -Tipo AVISO }
}
function Accion-FastStartupOff {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord
        Write-Log "Inicio rapido (Fast Startup) desactivado." -Tipo OK
    } catch { Write-Log "No se pudo desactivar el Inicio rapido." -Tipo AVISO }
}
function Accion-PantallaBloqueoOff {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "NoLockScreen" -Value 1 -Type DWord
        Write-Log "Pantalla de bloqueo desactivada." -Tipo OK
    } catch { Write-Log "No se pudo desactivar la pantalla de bloqueo." -Tipo AVISO }
}
function Accion-PantallaBloqueoOn {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "NoLockScreen" -ErrorAction SilentlyContinue }
        Write-Log "Pantalla de bloqueo reactivada." -Tipo OK
    } catch { Write-Log "No se pudo reactivar la pantalla de bloqueo." -Tipo AVISO }
}

# ---------------------------------------------------------------------------
#  PERSONALIZACION: fondo de pantalla, tema claro/oscuro, protector, sonidos
# ---------------------------------------------------------------------------

$Script:TipoWallpaperListo = $false
function Ensure-TipoWallpaper {
    if ($Script:TipoWallpaperListo) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;
public class DragonToolWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoWallpaperListo = $true
}

function Accion-CambiarFondoPantalla {
    try { Ensure-TipoWallpaper } catch {
        Write-Log "No se pudo preparar el cambio de fondo de pantalla: $($_.Exception.Message)" -Tipo ERROR
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    $dialogo = New-Object System.Windows.Forms.OpenFileDialog
    $dialogo.Title = "Selecciona la imagen para el fondo de pantalla"
    $dialogo.Filter = "Imagenes (*.jpg;*.jpeg;*.png;*.bmp)|*.jpg;*.jpeg;*.png;*.bmp"
    if ($dialogo.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $SPI_SETDESKWALLPAPER = 0x0014
        $SPIF_UPDATEINIFILE = 0x01
        $SPIF_SENDCHANGE = 0x02
        [DragonToolWallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $dialogo.FileName, ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)) | Out-Null
        Write-Log "Fondo de pantalla cambiado a: $($dialogo.FileName)" -Tipo OK
    } catch {
        Write-Log "No se pudo cambiar el fondo de pantalla: $($_.Exception.Message)" -Tipo ERROR
    }
}

function Accion-TemaOscuroOn {
    try {
        $ruta = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-ItemProperty -Path $ruta -Name "AppsUseLightTheme" -Value 0 -Type DWord
        Set-ItemProperty -Path $ruta -Name "SystemUsesLightTheme" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Tema oscuro activado (apps y sistema)." -Tipo OK
    } catch { Write-Log "No se pudo activar el tema oscuro." -Tipo AVISO }
}
function Accion-TemaClaroOn {
    try {
        $ruta = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-ItemProperty -Path $ruta -Name "AppsUseLightTheme" -Value 1 -Type DWord
        Set-ItemProperty -Path $ruta -Name "SystemUsesLightTheme" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Tema claro activado (apps y sistema)." -Tipo OK
    } catch { Write-Log "No se pudo activar el tema claro." -Tipo AVISO }
}

function Accion-AbrirConfigPersonalizacion {
    Start-Process "ms-settings:personalization"
    Write-Log "Configuracion de personalizacion de Windows abierta (colores, temas, fondo)." -Tipo OK
}
function Accion-AbrirConfigPantallaBloqueo {
    Start-Process "ms-settings:lockscreen"
    Write-Log "Configuracion de pantalla de bloqueo abierta." -Tipo OK
}
function Accion-AbrirConfigSonidos {
    Start-Process "mmsys.cpl"
    Write-Log "Configuracion de sonidos del sistema abierta." -Tipo OK
}
function Accion-AbrirConfigCursor {
    Start-Process "main.cpl"
    Write-Log "Configuracion del puntero del mouse abierta." -Tipo OK
}

# --- Explorador de archivos (ampliado) ---

function Accion-RutaCompletaOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Value 1 -Type DWord
        Write-Log "Ruta completa activada en la barra de titulo del Explorador." -Tipo OK
    } catch { Write-Log "No se pudo activar la ruta completa." -Tipo AVISO }
}
function Accion-RutaCompletaOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "Ruta completa desactivada en la barra de titulo del Explorador." -Tipo OK
    } catch { Write-Log "No se pudo desactivar la ruta completa." -Tipo AVISO }
}
function Accion-AbrirEsteEquipoOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1 -Type DWord
        Write-Log "El Explorador se abrira en 'Este equipo'." -Tipo OK
    } catch { Write-Log "No se pudo cambiar la pagina de inicio del Explorador." -Tipo AVISO }
}
function Accion-AbrirAccesoRapidoOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 2 -Type DWord
        Write-Log "El Explorador se abrira en 'Acceso rapido' (por defecto)." -Tipo OK
    } catch { Write-Log "No se pudo cambiar la pagina de inicio del Explorador." -Tipo AVISO }
}
function Accion-MostrarUnidadesVaciasOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideDrivesWithNoMedia" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Unidades sin medio (ej. lectores de tarjetas vacios) ahora se muestran." -Tipo OK
    } catch { Write-Log "No se pudo cambiar la visibilidad de unidades vacias." -Tipo AVISO }
}
function Accion-MostrarUnidadesVaciasOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideDrivesWithNoMedia" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Unidades sin medio ocultas (comportamiento por defecto)." -Tipo OK
    } catch { Write-Log "No se pudo ocultar las unidades vacias." -Tipo AVISO }
}
function Accion-CacheMiniaturasOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "DisableThumbnailCache" -Value 1 -Type DWord
        Write-Log "Cache de miniaturas desactivada (se mostraran iconos en vez de miniaturas)." -Tipo OK
    } catch { Write-Log "No se pudo desactivar la cache de miniaturas." -Tipo AVISO }
}
function Accion-CacheMiniaturasOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "DisableThumbnailCache" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "Cache de miniaturas reactivada." -Tipo OK
    } catch { Write-Log "No se pudo reactivar la cache de miniaturas." -Tipo AVISO }
}
function Accion-OcultarIconoEsteEquipoOn {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Icono 'Este equipo' ocultado del escritorio." -Tipo OK
    } catch { Write-Log "No se pudo ocultar el icono 'Este equipo'." -Tipo AVISO }
}
function Accion-OcultarIconoEsteEquipoOff {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Icono 'Este equipo' visible en el escritorio." -Tipo OK
    } catch { Write-Log "No se pudo mostrar el icono 'Este equipo'." -Tipo AVISO }
}
function Accion-OcultarIconoPapeleraOn {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "{645FF040-5081-101B-9F08-00AA002F954E}" -Value 1 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Icono 'Papelera de reciclaje' ocultado del escritorio." -Tipo OK
    } catch { Write-Log "No se pudo ocultar el icono de la papelera." -Tipo AVISO }
}
function Accion-OcultarIconoPapeleraOff {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "{645FF040-5081-101B-9F08-00AA002F954E}" -Value 0 -Type DWord
        Restart-ExplorerSilencioso
        Write-Log "Icono 'Papelera de reciclaje' visible en el escritorio." -Tipo OK
    } catch { Write-Log "No se pudo mostrar el icono de la papelera." -Tipo AVISO }
}

# --- Interfaz y animaciones ---

function Accion-MenuInstantaneoOn {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type String
        Write-Log "Menus instantaneos activados (sin retraso al abrir)." -Tipo OK
    } catch { Write-Log "No se pudo ajustar el retraso de menus." -Tipo AVISO }
}
function Accion-MenuInstantaneoOff {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "400" -Type String
        Write-Log "Retraso de menus restaurado al valor por defecto (400 ms)." -Tipo OK
    } catch { Write-Log "No se pudo restaurar el retraso de menus." -Tipo AVISO }
}
function Accion-AnimacionMinimizarOff {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Type String
        Write-Log "Animacion al minimizar/maximizar ventanas desactivada." -Tipo OK
    } catch { Write-Log "No se pudo desactivar la animacion de ventanas." -Tipo AVISO }
}
function Accion-AnimacionMinimizarOn {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1" -Type String
        Write-Log "Animacion al minimizar/maximizar ventanas activada." -Tipo OK
    } catch { Write-Log "No se pudo activar la animacion de ventanas." -Tipo AVISO }
}
function Accion-AnimacionTaskbarOff {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0 -Type DWord
        Write-Log "Animaciones de la barra de tareas desactivadas." -Tipo OK
    } catch { Write-Log "No se pudo desactivar las animaciones de la barra de tareas." -Tipo AVISO }
}
function Accion-AnimacionTaskbarOn {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 1 -Type DWord
        Write-Log "Animaciones de la barra de tareas activadas." -Tipo OK
    } catch { Write-Log "No se pudo activar las animaciones de la barra de tareas." -Tipo AVISO }
}
function Accion-ArrastreVentanaOn {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "1" -Type String
        Write-Log "Se mostrara el contenido de la ventana al arrastrarla." -Tipo OK
    } catch { Write-Log "No se pudo ajustar el arrastre de ventanas." -Tipo AVISO }
}
function Accion-ArrastreVentanaOff {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "0" -Type String
        Write-Log "Al arrastrar una ventana solo se mostrara su contorno (menos carga grafica)." -Tipo OK
    } catch { Write-Log "No se pudo ajustar el arrastre de ventanas." -Tipo AVISO }
}
function Accion-SalvapantallasOff {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "0" -Type String
        Write-Log "Protector de pantalla desactivado." -Tipo OK
    } catch { Write-Log "No se pudo desactivar el protector de pantalla." -Tipo AVISO }
}
function Accion-SalvapantallasOn {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "1" -Type String
        Write-Log "Protector de pantalla activado." -Tipo OK
    } catch { Write-Log "No se pudo activar el protector de pantalla." -Tipo AVISO }
}

# --- Privacidad (ampliado) ---

function Accion-HistorialActividadesOff {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "EnableActivityFeed" -Value 0 -Type DWord
        Set-ItemProperty -Path $path -Name "PublishUserActivities" -Value 0 -Type DWord
        Set-ItemProperty -Path $path -Name "UploadUserActivities" -Value 0 -Type DWord
        Write-Log "Historial de actividades (Timeline) desactivado." -Tipo OK
    } catch { Write-Log "No se pudo desactivar el historial de actividades." -Tipo AVISO }
}
function Accion-HistorialActividadesOn {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name "EnableActivityFeed" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $path -Name "PublishUserActivities" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $path -Name "UploadUserActivities" -ErrorAction SilentlyContinue
        }
        Write-Log "Historial de actividades restaurado por defecto." -Tipo OK
    } catch { Write-Log "No se pudo restaurar el historial de actividades." -Tipo AVISO }
}
function Accion-SugerenciasBusquedaOff {
    try {
        $path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord
        Write-Log "Sugerencias web en el cuadro de busqueda desactivadas." -Tipo OK
    } catch { Write-Log "No se pudo desactivar las sugerencias de busqueda." -Tipo AVISO }
}
function Accion-SugerenciasBusquedaOn {
    try {
        $path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue }
        Write-Log "Sugerencias web en el cuadro de busqueda reactivadas." -Tipo OK
    } catch { Write-Log "No se pudo reactivar las sugerencias de busqueda." -Tipo AVISO }
}
function Accion-PortapapelesNubeOff {
    try {
        $path = "HKCU:\Software\Microsoft\Clipboard"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "EnableClipboardHistory" -Value 0 -Type DWord
        Write-Log "Historial del portapapeles (Win+V) desactivado." -Tipo OK
    } catch { Write-Log "No se pudo desactivar el historial del portapapeles." -Tipo AVISO }
}
function Accion-PortapapelesNubeOn {
    try {
        $path = "HKCU:\Software\Microsoft\Clipboard"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "EnableClipboardHistory" -Value 1 -Type DWord
        Write-Log "Historial del portapapeles (Win+V) activado." -Tipo OK
    } catch { Write-Log "No se pudo activar el historial del portapapeles." -Tipo AVISO }
}
function Accion-CaracteristicasConsumidorOff {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
        Write-Log "Apps sugeridas / caracteristicas de consumidor desactivadas." -Tipo OK
    } catch { Write-Log "No se pudo desactivar las caracteristicas de consumidor (puede requerir Windows Pro/Enterprise)." -Tipo AVISO }
}
function Accion-CaracteristicasConsumidorOn {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "DisableWindowsConsumerFeatures" -ErrorAction SilentlyContinue }
        Write-Log "Caracteristicas de consumidor restauradas." -Tipo OK
    } catch { Write-Log "No se pudo restaurar las caracteristicas de consumidor." -Tipo AVISO }
}
function Accion-InformesErroresOff {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "Disabled" -Value 1 -Type DWord
        Write-Log "Informes de errores de Windows (WER) desactivados." -Tipo OK
    } catch { Write-Log "No se pudo desactivar los informes de errores." -Tipo AVISO }
}
function Accion-InformesErroresOn {
    try {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
        if (Test-Path $path) { Set-ItemProperty -Path $path -Name "Disabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue }
        Write-Log "Informes de errores de Windows (WER) reactivados." -Tipo OK
    } catch { Write-Log "No se pudo reactivar los informes de errores." -Tipo AVISO }
}
function Accion-CuentaLocalForzarOn {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "NoConnectedUser" -Value 3 -Type DWord
        Write-Log "Se impedira agregar o iniciar sesion con cuentas Microsoft (solo cuentas locales)." -Tipo OK
    } catch { Write-Log "No se pudo aplicar la restriccion de cuentas Microsoft." -Tipo AVISO }
}
function Accion-CuentaLocalForzarOff {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "NoConnectedUser" -ErrorAction SilentlyContinue }
        Write-Log "Restriccion de cuentas Microsoft eliminada." -Tipo OK
    } catch { Write-Log "No se pudo quitar la restriccion de cuentas Microsoft." -Tipo AVISO }
}

# --- Red ---

function Accion-AutorunUSBOff {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord
        Write-Log "Reproduccion automatica (Autorun/Autoplay) desactivada en todas las unidades." -Tipo OK
    } catch { Write-Log "No se pudo desactivar Autorun." -Tipo AVISO }
}
function Accion-AutorunUSBOn {
    try {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue }
        Write-Log "Reproduccion automatica restaurada por defecto." -Tipo OK
    } catch { Write-Log "No se pudo restaurar Autorun." -Tipo AVISO }
}
function Accion-IPv6Off {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 0xFF -Type DWord
        Write-Log "IPv6 desactivado (requiere reiniciar)." -Tipo OK
    } catch { Write-Log "No se pudo desactivar IPv6." -Tipo AVISO }
}
function Accion-IPv6On {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 0 -Type DWord
        Write-Log "IPv6 reactivado (requiere reiniciar)." -Tipo OK
    } catch { Write-Log "No se pudo reactivar IPv6." -Tipo AVISO }
}
function Accion-QoSLiberarAncho {
    if (-not (Requiere-Admin)) { return }
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "NonBestEffortLimit" -Value 0 -Type DWord
        Write-Log "Reserva de ancho de banda QoS liberada (0% reservado, antes 20% por defecto)." -Tipo OK
    } catch { Write-Log "No se pudo liberar la reserva de ancho de banda." -Tipo AVISO }
}
function Accion-QoSRestaurarAncho {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
        if (Test-Path $path) { Remove-ItemProperty -Path $path -Name "NonBestEffortLimit" -ErrorAction SilentlyContinue }
        Write-Log "Reserva de ancho de banda QoS restaurada por defecto." -Tipo OK
    } catch { Write-Log "No se pudo restaurar la reserva de ancho de banda." -Tipo AVISO }
}

# --- Seguridad (avanzado, usar con criterio) ---

function Accion-UACOff {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "ADVERTENCIA: desactivar el Control de cuentas de usuario (UAC) reduce significativamente la seguridad de Windows, ya que las apps podran hacer cambios administrativos sin avisarte. Solo se recomienda en casos muy puntuales. ¿Deseas continuar de todas formas?")) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0 -Type DWord
        Write-Log "UAC desactivado (requiere reiniciar). Recuerda que esto reduce la seguridad del equipo." -Tipo AVISO
    } catch { Write-Log "No se pudo desactivar UAC." -Tipo AVISO }
}
function Accion-UACOn {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1 -Type DWord
        Write-Log "UAC reactivado (requiere reiniciar). Configuracion de seguridad recomendada." -Tipo OK
    } catch { Write-Log "No se pudo reactivar UAC." -Tipo AVISO }
}

$Script:ChecklistRegistro = @(
    @{ Categoria='Explorador de archivos'; Nombre='Mostrar extensiones de archivo'; Tipo='Accion'; ValorOn='Accion-MostrarExtensionesOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Ocultar extensiones de archivo (por defecto)'; Tipo='Accion'; ValorOn='Accion-MostrarExtensionesOff' },
    @{ Categoria='Explorador de archivos'; Nombre='Mostrar archivos y carpetas ocultos'; Tipo='Accion'; ValorOn='Accion-MostrarOcultosOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Ocultar archivos y carpetas ocultos (por defecto)'; Tipo='Accion'; ValorOn='Accion-MostrarOcultosOff' },
    @{ Categoria='Explorador de archivos'; Nombre='Desactivar archivos/carpetas recientes en Acceso rapido'; Tipo='Accion'; ValorOn='Accion-RecientesOff' },
    @{ Categoria='Explorador de archivos'; Nombre='Reactivar archivos/carpetas recientes en Acceso rapido'; Tipo='Accion'; ValorOn='Accion-RecientesOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Mostrar ruta completa en la barra de titulo'; Tipo='Accion'; ValorOn='Accion-RutaCompletaOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Ocultar ruta completa en la barra de titulo'; Tipo='Accion'; ValorOn='Accion-RutaCompletaOff' },
    @{ Categoria='Explorador de archivos'; Nombre='Abrir el Explorador en "Este equipo"'; Tipo='Accion'; ValorOn='Accion-AbrirEsteEquipoOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Abrir el Explorador en "Acceso rapido" (por defecto)'; Tipo='Accion'; ValorOn='Accion-AbrirAccesoRapidoOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Mostrar unidades sin medio (lectores de tarjetas vacios, etc.)'; Tipo='Accion'; ValorOn='Accion-MostrarUnidadesVaciasOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Ocultar unidades sin medio (por defecto)'; Tipo='Accion'; ValorOn='Accion-MostrarUnidadesVaciasOff' },
    @{ Categoria='Explorador de archivos'; Nombre='Desactivar cache de miniaturas (mostrar iconos genericos)'; Tipo='Accion'; ValorOn='Accion-CacheMiniaturasOff' },
    @{ Categoria='Explorador de archivos'; Nombre='Reactivar cache de miniaturas'; Tipo='Accion'; ValorOn='Accion-CacheMiniaturasOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Ocultar icono "Este equipo" del escritorio'; Tipo='Accion'; ValorOn='Accion-OcultarIconoEsteEquipoOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Mostrar icono "Este equipo" en el escritorio'; Tipo='Accion'; ValorOn='Accion-OcultarIconoEsteEquipoOff' },
    @{ Categoria='Explorador de archivos'; Nombre='Ocultar icono "Papelera de reciclaje" del escritorio'; Tipo='Accion'; ValorOn='Accion-OcultarIconoPapeleraOn' },
    @{ Categoria='Explorador de archivos'; Nombre='Mostrar icono "Papelera de reciclaje" en el escritorio'; Tipo='Accion'; ValorOn='Accion-OcultarIconoPapeleraOff' },

    @{ Categoria='Interfaz y animaciones'; Nombre='Menus instantaneos (sin retraso)'; Tipo='Accion'; ValorOn='Accion-MenuInstantaneoOn' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Restaurar retraso de menus por defecto'; Tipo='Accion'; ValorOn='Accion-MenuInstantaneoOff' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Desactivar animacion al minimizar/maximizar ventanas'; Tipo='Accion'; ValorOn='Accion-AnimacionMinimizarOff' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Activar animacion al minimizar/maximizar ventanas'; Tipo='Accion'; ValorOn='Accion-AnimacionMinimizarOn' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Desactivar animaciones de la barra de tareas'; Tipo='Accion'; ValorOn='Accion-AnimacionTaskbarOff' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Activar animaciones de la barra de tareas'; Tipo='Accion'; ValorOn='Accion-AnimacionTaskbarOn' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Mostrar contenido de la ventana al arrastrarla'; Tipo='Accion'; ValorOn='Accion-ArrastreVentanaOn' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Mostrar solo el contorno al arrastrar ventanas (menos carga grafica)'; Tipo='Accion'; ValorOn='Accion-ArrastreVentanaOff' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Desactivar protector de pantalla'; Tipo='Accion'; ValorOn='Accion-SalvapantallasOff' },
    @{ Categoria='Interfaz y animaciones'; Nombre='Activar protector de pantalla'; Tipo='Accion'; ValorOn='Accion-SalvapantallasOn' },

    @{ Categoria='Privacidad'; Nombre='Reducir telemetria de Windows al minimo'; Tipo='Accion'; ValorOn='Accion-TelemetriaMinima' },
    @{ Categoria='Privacidad'; Nombre='Restaurar telemetria de Windows por defecto'; Tipo='Accion'; ValorOn='Accion-TelemetriaRestaurar' },
    @{ Categoria='Privacidad'; Nombre='Desactivar ID de publicidad (anuncios personalizados)'; Tipo='Accion'; ValorOn='Accion-AdvertisingIdOff' },
    @{ Categoria='Privacidad'; Nombre='Activar ID de publicidad'; Tipo='Accion'; ValorOn='Accion-AdvertisingIdOn' },
    @{ Categoria='Privacidad'; Nombre='Desactivar Cortana'; Tipo='Accion'; ValorOn='Accion-CortanaOff' },
    @{ Categoria='Privacidad'; Nombre='Reactivar Cortana'; Tipo='Accion'; ValorOn='Accion-CortanaOn' },
    @{ Categoria='Privacidad'; Nombre='Desactivar historial de actividades (Timeline)'; Tipo='Accion'; ValorOn='Accion-HistorialActividadesOff' },
    @{ Categoria='Privacidad'; Nombre='Reactivar historial de actividades (Timeline)'; Tipo='Accion'; ValorOn='Accion-HistorialActividadesOn' },
    @{ Categoria='Privacidad'; Nombre='Desactivar sugerencias web en el cuadro de busqueda'; Tipo='Accion'; ValorOn='Accion-SugerenciasBusquedaOff' },
    @{ Categoria='Privacidad'; Nombre='Reactivar sugerencias web en el cuadro de busqueda'; Tipo='Accion'; ValorOn='Accion-SugerenciasBusquedaOn' },
    @{ Categoria='Privacidad'; Nombre='Desactivar historial del portapapeles (Win+V)'; Tipo='Accion'; ValorOn='Accion-PortapapelesNubeOff' },
    @{ Categoria='Privacidad'; Nombre='Activar historial del portapapeles (Win+V)'; Tipo='Accion'; ValorOn='Accion-PortapapelesNubeOn' },
    @{ Categoria='Privacidad'; Nombre='Desactivar apps sugeridas / caracteristicas de consumidor'; Tipo='Accion'; ValorOn='Accion-CaracteristicasConsumidorOff' },
    @{ Categoria='Privacidad'; Nombre='Reactivar apps sugeridas / caracteristicas de consumidor'; Tipo='Accion'; ValorOn='Accion-CaracteristicasConsumidorOn' },
    @{ Categoria='Privacidad'; Nombre='Desactivar informes de errores de Windows (WER)'; Tipo='Accion'; ValorOn='Accion-InformesErroresOff' },
    @{ Categoria='Privacidad'; Nombre='Reactivar informes de errores de Windows (WER)'; Tipo='Accion'; ValorOn='Accion-InformesErroresOn' },
    @{ Categoria='Privacidad'; Nombre='Forzar solo cuentas locales (bloquear cuentas Microsoft)'; Tipo='Accion'; ValorOn='Accion-CuentaLocalForzarOn' },
    @{ Categoria='Privacidad'; Nombre='Permitir cuentas Microsoft de nuevo'; Tipo='Accion'; ValorOn='Accion-CuentaLocalForzarOff' },

    @{ Categoria='Rendimiento e inicio'; Nombre='Activar Inicio rapido (Fast Startup)'; Tipo='Accion'; ValorOn='Accion-FastStartupOn' },
    @{ Categoria='Rendimiento e inicio'; Nombre='Desactivar Inicio rapido (Fast Startup)'; Tipo='Accion'; ValorOn='Accion-FastStartupOff' },

    @{ Categoria='Pantalla de bloqueo'; Nombre='Desactivar pantalla de bloqueo'; Tipo='Accion'; ValorOn='Accion-PantallaBloqueoOff' },
    @{ Categoria='Pantalla de bloqueo'; Nombre='Reactivar pantalla de bloqueo'; Tipo='Accion'; ValorOn='Accion-PantallaBloqueoOn' },

    @{ Categoria='Red'; Nombre='Desactivar reproduccion automatica (Autorun/Autoplay) en USB y otras unidades'; Tipo='Accion'; ValorOn='Accion-AutorunUSBOff' },
    @{ Categoria='Red'; Nombre='Reactivar reproduccion automatica'; Tipo='Accion'; ValorOn='Accion-AutorunUSBOn' },
    @{ Categoria='Red'; Nombre='Desactivar IPv6 (prioriza IPv4, requiere reiniciar)'; Tipo='Accion'; ValorOn='Accion-IPv6Off' },
    @{ Categoria='Red'; Nombre='Reactivar IPv6 (requiere reiniciar)'; Tipo='Accion'; ValorOn='Accion-IPv6On' },
    @{ Categoria='Red'; Nombre='Liberar reserva de ancho de banda QoS (0% en vez del 20% por defecto)'; Tipo='Accion'; ValorOn='Accion-QoSLiberarAncho' },
    @{ Categoria='Red'; Nombre='Restaurar reserva de ancho de banda QoS por defecto'; Tipo='Accion'; ValorOn='Accion-QoSRestaurarAncho' },

    @{ Categoria='Seguridad (avanzado)'; Nombre='Desactivar UAC (reduce la seguridad, no recomendado)'; Tipo='Accion'; ValorOn='Accion-UACOff' },
    @{ Categoria='Seguridad (avanzado)'; Nombre='Reactivar UAC (configuracion recomendada)'; Tipo='Accion'; ValorOn='Accion-UACOn' }
)

function Accion-AbrirRegedit {
    Start-Process "regedit.exe"
    Write-Log "Editor del Registro (regedit) abierto." -Tipo OK
}

# --- Optimizacion de registro (rendimiento) ---
# Ajustes de registro enfocados especificamente en rendimiento, distintos de
# los de la seccion "Edicion del registro" (que son mas de interfaz/privacidad).

function Accion-NtfsUltimoAccesoOff {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisableLastAccessUpdate" -Value 1 -Type DWord
        Write-Log "Actualizacion de 'ultimo acceso' en NTFS desactivada (menos escritura en disco)." -Tipo OK
    } catch { Write-Log "No se pudo aplicar el ajuste de NTFS." -Tipo AVISO }
}
function Accion-NtfsUltimoAccesoOn {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisableLastAccessUpdate" -Value 0 -Type DWord
        Write-Log "Actualizacion de 'ultimo acceso' en NTFS reactivada." -Tipo OK
    } catch { Write-Log "No se pudo revertir el ajuste de NTFS." -Tipo AVISO }
}

function Accion-NoPaginarNucleoOn {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1 -Type DWord
        Write-Log "Nucleo y controladores se mantendran en RAM en vez de paginarse a disco (requiere reiniciar)." -Tipo OK
    } catch { Write-Log "No se pudo aplicar el ajuste de memoria." -Tipo AVISO }
}
function Accion-NoPaginarNucleoOff {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 0 -Type DWord
        Write-Log "Paginado de nucleo/controladores restaurado por defecto (requiere reiniciar)." -Tipo OK
    } catch { Write-Log "No se pudo revertir el ajuste de memoria." -Tipo AVISO }
}

function Accion-MemoriaOptimizarProgramas {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -Type DWord
        Write-Log "Memoria optimizada para programas en vez de cache de archivos (requiere reiniciar)." -Tipo OK
    } catch { Write-Log "No se pudo aplicar el ajuste de memoria." -Tipo AVISO }
}
function Accion-MemoriaOptimizarArchivosCompartidos {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 1 -Type DWord
        Write-Log "Memoria optimizada para cache de archivos compartidos (recomendado solo si este equipo comparte archivos en red; requiere reiniciar)." -Tipo OK
    } catch { Write-Log "No se pudo aplicar el ajuste de memoria." -Tipo AVISO }
}

function Accion-PrefetchCompletoOn {
    if (-not (Requiere-Admin)) { return }
    try {
        $ruta = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
        Set-ItemProperty -Path $ruta -Name "EnablePrefetcher" -Value 3 -Type DWord
        Set-ItemProperty -Path $ruta -Name "EnableSuperfetch" -Value 3 -Type DWord
        Write-Log "Prefetch/Superfetch activado completo (aplicaciones + arranque)." -Tipo OK
    } catch { Write-Log "No se pudo ajustar Prefetch." -Tipo AVISO }
}
function Accion-PrefetchDesactivar {
    if (-not (Requiere-Admin)) { return }
    try {
        $ruta = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
        Set-ItemProperty -Path $ruta -Name "EnablePrefetcher" -Value 0 -Type DWord
        Set-ItemProperty -Path $ruta -Name "EnableSuperfetch" -Value 0 -Type DWord
        Write-Log "Prefetch/Superfetch desactivado (recomendado en unidades SSD)." -Tipo OK
    } catch { Write-Log "No se pudo ajustar Prefetch." -Tipo AVISO }
}

function Accion-TiempoEsperaAppsReducir {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -Value "1000" -Type String
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "2000" -Type String
        Write-Log "Tiempo de espera para cerrar aplicaciones que no responden reducido." -Tipo OK
    } catch { Write-Log "No se pudo reducir el tiempo de espera de aplicaciones." -Tipo AVISO }
}
function Accion-TiempoEsperaAppsRestaurar {
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -Value "5000" -Type String
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "20000" -Type String
        Write-Log "Tiempo de espera de aplicaciones restaurado por defecto." -Tipo OK
    } catch { Write-Log "No se pudo restaurar el tiempo de espera de aplicaciones." -Tipo AVISO }
}

function Accion-TiempoEsperaServiciosReducir {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "2000" -Type String
        Write-Log "Tiempo de espera para finalizar servicios al apagar reducido (apagado mas rapido)." -Tipo OK
    } catch { Write-Log "No se pudo reducir el tiempo de espera de servicios." -Tipo AVISO }
}
function Accion-TiempoEsperaServiciosRestaurar {
    if (-not (Requiere-Admin)) { return }
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "5000" -Type String
        Write-Log "Tiempo de espera de servicios restaurado por defecto." -Tipo OK
    } catch { Write-Log "No se pudo restaurar el tiempo de espera de servicios." -Tipo AVISO }
}

function Accion-RetrasoInicioAppsOff {
    try {
        $ruta = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
        if (-not (Test-Path $ruta)) { New-Item -Path $ruta -Force | Out-Null }
        Set-ItemProperty -Path $ruta -Name "StartupDelayInMSec" -Value 0 -Type DWord
        Write-Log "Retraso artificial de inicio de apps en segundo plano eliminado." -Tipo OK
    } catch { Write-Log "No se pudo eliminar el retraso de inicio." -Tipo AVISO }
}
function Accion-RetrasoInicioAppsOn {
    try {
        $ruta = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
        if (Test-Path $ruta) { Remove-ItemProperty -Path $ruta -Name "StartupDelayInMSec" -ErrorAction SilentlyContinue }
        Write-Log "Retraso de inicio de apps restaurado por defecto." -Tipo OK
    } catch { Write-Log "No se pudo restaurar el retraso de inicio." -Tipo AVISO }
}

function Accion-DesactivarNagleOn {
    if (-not (Requiere-Admin)) { return }
    try {
        $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction Stop
        foreach ($i in $interfaces) {
            Set-ItemProperty -Path $i.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $i.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
        Write-Log "Algoritmo de Nagle desactivado en todas las interfaces de red (menor latencia, mas paquetes pequeños)." -Tipo OK
    } catch { Write-Log "No se pudo desactivar el algoritmo de Nagle." -Tipo AVISO }
}
function Accion-DesactivarNagleOff {
    if (-not (Requiere-Admin)) { return }
    try {
        $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction Stop
        foreach ($i in $interfaces) {
            Remove-ItemProperty -Path $i.PSPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $i.PSPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue
        }
        Write-Log "Algoritmo de Nagle restaurado por defecto en todas las interfaces de red." -Tipo OK
    } catch { Write-Log "No se pudo restaurar el algoritmo de Nagle." -Tipo AVISO }
}

function Accion-CacheIconosAumentar {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "Max Cached Icons" -Value "4096" -Type String
        Restart-ExplorerSilencioso
        Write-Log "Cache de iconos aumentada (menos parpadeo/regeneracion de iconos en el Explorador)." -Tipo OK
    } catch { Write-Log "No se pudo aumentar la cache de iconos." -Tipo AVISO }
}
function Accion-CacheIconosRestaurar {
    try {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "Max Cached Icons" -ErrorAction SilentlyContinue
        Restart-ExplorerSilencioso
        Write-Log "Cache de iconos restaurada por defecto." -Tipo OK
    } catch { Write-Log "No se pudo restaurar la cache de iconos." -Tipo AVISO }
}

$Script:ChecklistOptimizacionRegistro = @(
    @{ Categoria='Disco'; Nombre='Desactivar actualizacion de "ultimo acceso" en NTFS (menos escritura en disco)'; Tipo='Accion'; ValorOn='Accion-NtfsUltimoAccesoOff' },
    @{ Categoria='Disco'; Nombre='Reactivar actualizacion de "ultimo acceso" en NTFS'; Tipo='Accion'; ValorOn='Accion-NtfsUltimoAccesoOn' },

    @{ Categoria='Memoria'; Nombre='Mantener nucleo/controladores en RAM (no paginar a disco)'; Tipo='Accion'; ValorOn='Accion-NoPaginarNucleoOn' },
    @{ Categoria='Memoria'; Nombre='Restaurar paginado normal de nucleo/controladores'; Tipo='Accion'; ValorOn='Accion-NoPaginarNucleoOff' },
    @{ Categoria='Memoria'; Nombre='Optimizar memoria para programas (recomendado)'; Tipo='Accion'; ValorOn='Accion-MemoriaOptimizarProgramas' },
    @{ Categoria='Memoria'; Nombre='Optimizar memoria para archivos compartidos en red'; Tipo='Accion'; ValorOn='Accion-MemoriaOptimizarArchivosCompartidos' },
    @{ Categoria='Memoria'; Nombre='Activar Prefetch/Superfetch completo'; Tipo='Accion'; ValorOn='Accion-PrefetchCompletoOn' },
    @{ Categoria='Memoria'; Nombre='Desactivar Prefetch/Superfetch (recomendado en SSD)'; Tipo='Accion'; ValorOn='Accion-PrefetchDesactivar' },

    @{ Categoria='Respuesta del sistema'; Nombre='Reducir tiempo de espera de apps que no responden'; Tipo='Accion'; ValorOn='Accion-TiempoEsperaAppsReducir' },
    @{ Categoria='Respuesta del sistema'; Nombre='Restaurar tiempo de espera de apps por defecto'; Tipo='Accion'; ValorOn='Accion-TiempoEsperaAppsRestaurar' },
    @{ Categoria='Respuesta del sistema'; Nombre='Reducir tiempo de espera de servicios al apagar'; Tipo='Accion'; ValorOn='Accion-TiempoEsperaServiciosReducir' },
    @{ Categoria='Respuesta del sistema'; Nombre='Restaurar tiempo de espera de servicios por defecto'; Tipo='Accion'; ValorOn='Accion-TiempoEsperaServiciosRestaurar' },
    @{ Categoria='Respuesta del sistema'; Nombre='Eliminar retraso artificial de inicio de apps en segundo plano'; Tipo='Accion'; ValorOn='Accion-RetrasoInicioAppsOff' },
    @{ Categoria='Respuesta del sistema'; Nombre='Restaurar retraso de inicio de apps por defecto'; Tipo='Accion'; ValorOn='Accion-RetrasoInicioAppsOn' },

    @{ Categoria='Red'; Nombre='Desactivar algoritmo de Nagle (menor latencia de red)'; Tipo='Accion'; ValorOn='Accion-DesactivarNagleOn' },
    @{ Categoria='Red'; Nombre='Restaurar algoritmo de Nagle por defecto'; Tipo='Accion'; ValorOn='Accion-DesactivarNagleOff' },

    @{ Categoria='Explorador de archivos'; Nombre='Aumentar cache de iconos'; Tipo='Accion'; ValorOn='Accion-CacheIconosAumentar' },
    @{ Categoria='Explorador de archivos'; Nombre='Restaurar cache de iconos por defecto'; Tipo='Accion'; ValorOn='Accion-CacheIconosRestaurar' }
)

# --- Analisis y reparacion de errores del registro ---

function Test-RutaEnCadena {
    param([string]$Cadena)
    if ([string]::IsNullOrWhiteSpace($Cadena)) { return $true }
    $limpio = $Cadena.Trim()

    # Los desinstaladores basados en msiexec no apuntan a un archivo en disco,
    # sino a un GUID de producto registrado en Windows Installer: no hay
    # ninguna ruta de archivo que verificar, asi que se consideran validos.
    if ($limpio -match '(?i)msiexec(\.exe)?') { return $true }

    # Si el valor empieza entre comillas, la ruta real es exactamente lo que
    # hay dentro de las comillas (independientemente de argumentos que vengan
    # despues, p.ej. "C:\...\uninst.exe" /S). Esto evita que argumentos como
    # /X o /S queden pegados a la ruta y hagan fallar Test-Path por error.
    if ($limpio -match '^"([^"]+)"') {
        $rutaPosible = $Matches[1]
    } elseif ($limpio -match '^(.*?\.(exe|dll|com|msi|bat|cmd))\b') {
        $rutaPosible = $Matches[1]
    } else {
        $rutaPosible = $limpio
    }
    $rutaPosible = $rutaPosible.Trim().Trim('"')

    if ($rutaPosible -match '^[A-Za-z]:\\' -or $rutaPosible -match '^\\\\') {
        return (Test-Path -LiteralPath $rutaPosible -ErrorAction SilentlyContinue)
    }
    return $true
}

function Get-ErroresRegistroInicio {
    $resultado = @()
    $rutas = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($ruta in $rutas) {
        if (-not (Test-Path $ruta)) { continue }
        $item = Get-Item -Path $ruta -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($nombre in $item.Property) {
            $valor = (Get-ItemProperty -Path $ruta -Name $nombre -ErrorAction SilentlyContinue).$nombre
            if (-not (Test-RutaEnCadena -Cadena $valor)) {
                $resultado += [PSCustomObject]@{
                    Categoria   = "Programa de inicio roto"
                    Descripcion = "'$nombre' apunta a un archivo que ya no existe"
                    Ruta        = $ruta
                    Valor       = $nombre
                    Detalle     = $valor
                }
            }
        }
    }
    return $resultado
}

function Get-ErroresRegistroDesinstalacion {
    $resultado = @()
    $rutas = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($patron in $rutas) {
        $claves = Get-ItemProperty -Path $patron -ErrorAction SilentlyContinue
        foreach ($c in $claves) {
            $nombre = $c.DisplayName
            if (-not $nombre) { continue }
            $ejecutable = $c.UninstallString
            if ($ejecutable -and -not (Test-RutaEnCadena -Cadena $ejecutable)) {
                $resultado += [PSCustomObject]@{
                    Categoria   = "Entrada de desinstalacion huerfana"
                    Descripcion = "'$nombre' tiene un desinstalador que ya no existe"
                    Ruta        = $c.PSPath
                    Valor       = $null
                    Detalle     = $ejecutable
                }
            }
        }
    }
    return $resultado
}

function Get-ErroresRegistroSharedDLLs {
    $resultado = @()
    $ruta = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs'
    if (Test-Path $ruta) {
        $item = Get-Item -Path $ruta -ErrorAction SilentlyContinue
        if ($item) {
            foreach ($nombre in $item.Property) {
                if (-not (Test-Path -LiteralPath $nombre -ErrorAction SilentlyContinue)) {
                    $resultado += [PSCustomObject]@{
                        Categoria   = "DLL compartida huerfana"
                        Descripcion = "Referencia a un archivo que ya no existe"
                        Ruta        = $ruta
                        Valor       = $nombre
                        Detalle     = $nombre
                    }
                }
            }
        }
    }
    return $resultado
}

function Get-ErroresRegistroServicios {
    $resultado = @()
    try {
        $servicios = Get-CimInstance Win32_Service -ErrorAction Stop -Property Name,DisplayName,PathName
        foreach ($s in $servicios) {
            if ($s.PathName -and -not (Test-RutaEnCadena -Cadena $s.PathName)) {
                $resultado += [PSCustomObject]@{
                    Categoria   = "Servicio con ruta invalida (solo informativo)"
                    Descripcion = "El servicio '$($s.DisplayName)' apunta a un archivo que no existe"
                    Ruta        = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)"
                    Valor       = "ImagePath"
                    Detalle     = $s.PathName
                }
            }
        }
    } catch {}
    return $resultado
}

function Get-ErroresRegistroCompleto {
    $todos = @()
    $todos += Get-ErroresRegistroInicio
    $todos += Get-ErroresRegistroDesinstalacion
    $todos += Get-ErroresRegistroSharedDLLs
    $todos += Get-ErroresRegistroServicios
    return $todos
}

# ---------------------------------------------------------------------------
#  ACELERAR FUNCIONAMIENTO DEL PROCESADOR
# ---------------------------------------------------------------------------

function Accion-AcelerarProcesador {
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Esto ajusta Windows para que el procesador trabaje de forma mas eficiente: plan de Alto rendimiento, nucleos sin 'estacionar' (core parking desactivado), frecuencia minima al 100% para evitar la latencia de arranque, y prioridad para las apps en primer plano.`n`n¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Acelerando el procesador"

    Update-VentanaProgreso -Ventana $prog -Porcentaje 15 -Estado "Activando plan de energia de Alto rendimiento..."
    try {
        powercfg -setactive SCHEME_MIN
        Write-Log "Plan de energia establecido en Alto rendimiento." -Tipo OK
        Update-VentanaProgreso -Ventana $prog -Porcentaje 15 -Estado "Plan de energia activado" -LogLinea "Plan de energia: Alto rendimiento."
    } catch { Write-Log "No se pudo cambiar el plan de energia." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 40 -Estado "Desactivando el 'estacionamiento' de nucleos (core parking)..."
    try {
        powercfg -setacvalueindex scheme_current sub_processor 0cc5b647-c1df-4637-891a-dec35c318583 100 | Out-Null
        powercfg -setdcvalueindex scheme_current sub_processor 0cc5b647-c1df-4637-891a-dec35c318583 100 | Out-Null
        powercfg -setactive scheme_current | Out-Null
        Write-Log "Core parking desactivado: todos los nucleos disponibles de inmediato." -Tipo OK
        Update-VentanaProgreso -Ventana $prog -Porcentaje 40 -Estado "Core parking desactivado" -LogLinea "Todos los nucleos del procesador quedan disponibles sin demora."
    } catch { Write-Log "No se pudo ajustar el core parking (puede no ser compatible con tu CPU)." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 65 -Estado "Ajustando el estado minimo del procesador al 100%..."
    try {
        powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100 | Out-Null
        powercfg -setactive scheme_current | Out-Null
        Write-Log "Estado minimo del procesador ajustado al 100% (evita la 'demora' al subir de frecuencia)." -Tipo OK
        Update-VentanaProgreso -Ventana $prog -Porcentaje 65 -Estado "Frecuencia minima ajustada" -LogLinea "El procesador ya no reduce su frecuencia en reposo."
    } catch { Write-Log "No se pudo ajustar el estado minimo del procesador." -Tipo AVISO }

    Update-VentanaProgreso -Ventana $prog -Porcentaje 90 -Estado "Priorizando CPU para aplicaciones en primer plano..."
    Accion-PriorizarPrimerPlano
    Update-VentanaProgreso -Ventana $prog -Porcentaje 90 -Estado "Prioridad ajustada" -LogLinea "CPU priorizada para la aplicacion activa."

    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Procesador optimizado."
    Write-Log "Optimizacion del procesador aplicada." -Tipo OK
    Show-Aviso "El procesador quedo configurado para trabajar de forma mas eficiente.`n`nAviso: en laptops esto aumenta el consumo de bateria a cambio de mas velocidad. Puedes revertirlo desde 'Restaurar configuracion predeterminada'." "Procesador optimizado"
}

# ---------------------------------------------------------------------------
#  LIBERAR RAM (Basica / Intermedia / Exhaustiva)
# ---------------------------------------------------------------------------

# P/Invoke para vaciar el "working set" de procesos (psapi.dll) y purgar la
# lista en espera de memoria del sistema (ntdll.dll) - la misma tecnica que
# usan herramientas conocidas de limpieza de RAM (ej. RAMMap de Sysinternals).
$Script:TipoLimpiadorRAM = $null
function Ensure-TipoLimpiadorRAM {
    if ($Script:TipoLimpiadorRAM) { return }
    $codigo = @"
using System;
using System.Runtime.InteropServices;

public class DragonToolMemUtils {
    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hProcess);

    [DllImport("ntdll.dll")]
    public static extern int NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);

    public static bool PurgeStandbyList() {
        // SystemMemoryListInformation = 80, MemoryPurgeStandbyList = 4
        int command = 4;
        IntPtr ptr = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(ptr, command);
        int resultado = NtSetSystemInformation(80, ptr, 4);
        Marshal.FreeHGlobal(ptr);
        return resultado == 0;
    }
}
"@
    Add-Type -TypeDefinition $codigo -ErrorAction Stop
    $Script:TipoLimpiadorRAM = $true
}

function Accion-LiberarRAM {
    param([ValidateSet('Basica','Intermedia','Exhaustiva')][string]$Modo)

    $descripciones = @{
        'Basica'     = "Vacia la memoria en uso de las aplicaciones abiertas (working set) sin cerrarlas. Rapido y seguro."
        'Intermedia' = "Ademas de lo anterior, limpia cache de DNS y miniaturas para liberar mas recursos."
        'Exhaustiva' = "Ademas de lo anterior, purga la lista de memoria en espera (standby list) del sistema completo. Es el modo mas agresivo."
    }
    if (-not (Show-Confirm "Modo $Modo`: $($descripciones[$Modo])`n`n¿Continuar?")) { return }
    if ($Modo -eq 'Exhaustiva' -and -not (Requiere-Admin)) { return }

    $prog = New-VentanaProgreso -Titulo "Liberando RAM (modo $Modo)"
    try {
        Ensure-TipoLimpiadorRAM
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error"
        Write-Log "No se pudo preparar la herramienta de limpieza de RAM: $($_.Exception.Message)" -Tipo ERROR
        return
    }

    $antes = Get-CimInstance Win32_OperatingSystem
    $ramLibreAntes = [math]::Round($antes.FreePhysicalMemory / 1MB, 2)

    Update-VentanaProgreso -Ventana $prog -Porcentaje 5 -Estado "Analizando procesos en ejecucion..." -LogLinea "RAM libre antes: $ramLibreAntes GB"
    $procesos = @(Get-Process | Where-Object { $_.Id -ne $PID })
    $total = [math]::Max($procesos.Count, 1)
    $i = 0
    foreach ($p in $procesos) {
        $i++
        $pct = 5 + [math]::Round(($i / $total) * 55)
        try {
            [DragonToolMemUtils]::EmptyWorkingSet($p.Handle) | Out-Null
        } catch {}
        if ($i % 5 -eq 0 -or $i -eq $total) {
            Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Vaciando memoria de procesos... ($i / $total)"
        }
    }
    Update-VentanaProgreso -Ventana $prog -Porcentaje 60 -Estado "Memoria de procesos liberada." -LogLinea "Working set liberado en $total proceso(s)."

    if ($Modo -eq 'Intermedia' -or $Modo -eq 'Exhaustiva') {
        Update-VentanaProgreso -Ventana $prog -Porcentaje 70 -Estado "Limpiando cache de DNS..."
        try { ipconfig /flushdns | Out-Null; Update-VentanaProgreso -Ventana $prog -Porcentaje 70 -Estado "Cache DNS limpiada" -LogLinea "Cache DNS vaciada." } catch {}

        Update-VentanaProgreso -Ventana $prog -Porcentaje 80 -Estado "Limpiando cache de miniaturas..."
        try {
            Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
            Update-VentanaProgreso -Ventana $prog -Porcentaje 80 -Estado "Cache de miniaturas limpiada" -LogLinea "Cache de miniaturas eliminada."
        } catch {}
    }

    if ($Modo -eq 'Exhaustiva') {
        Update-VentanaProgreso -Ventana $prog -Porcentaje 90 -Estado "Purgando la lista de memoria en espera del sistema (standby list)..."
        try {
            $exito = [DragonToolMemUtils]::PurgeStandbyList()
            if ($exito) {
                Update-VentanaProgreso -Ventana $prog -Porcentaje 95 -Estado "Lista en espera purgada" -LogLinea "Standby list del sistema purgada correctamente."
            } else {
                Update-VentanaProgreso -Ventana $prog -Porcentaje 95 -Estado "No se pudo purgar por completo" -LogLinea "El sistema no permitio purgar la standby list por completo (no es critico)."
            }
        } catch {
            Update-VentanaProgreso -Ventana $prog -Porcentaje 95 -Estado "No se pudo purgar la lista en espera" -LogLinea "Error al purgar standby list: $($_.Exception.Message)"
        }
    }

    Start-Sleep -Milliseconds 300
    $despues = Get-CimInstance Win32_OperatingSystem
    $ramLibreDespues = [math]::Round($despues.FreePhysicalMemory / 1MB, 2)
    $liberado = [math]::Round($ramLibreDespues - $ramLibreAntes, 2)
    $resumen = "RAM libre: $ramLibreAntes GB -> $ramLibreDespues GB (aprox. $liberado GB liberados)."

    Close-VentanaProgreso -Ventana $prog -MensajeFinal $resumen
    Write-Log "Liberacion de RAM ($Modo) completada. $resumen" -Tipo OK
    Show-Aviso "Liberacion de RAM completada.`n$resumen" "RAM liberada"
}

# ---------------------------------------------------------------------------
#  BUSCADOR DE CONTROLADORES POR HARDWARE
# ---------------------------------------------------------------------------

function Get-FabricanteDesdePNPID {
    param([string]$PnpId)
    if     ($PnpId -match 'VEN_10DE') { return 'NVIDIA' }
    elseif ($PnpId -match 'VEN_1002|VEN_1022') { return 'AMD' }
    elseif ($PnpId -match 'VEN_8086') { return 'Intel' }
    else { return 'Desconocido' }
}

function Get-InfoGPU {
    try {
        Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
            [PSCustomObject]@{
                Nombre        = $_.Name
                Fabricante    = Get-FabricanteDesdePNPID $_.PNPDeviceID
                DriverVersion = $_.DriverVersion
            }
        }
    } catch { @() }
}

function Get-InfoPlaca {
    try {
        $bb   = Get-CimInstance Win32_BaseBoard -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Fabricante  = $bb.Manufacturer
            Modelo      = $bb.Product
            BIOSVersion = $bios.SMBIOSBIOSVersion
        }
    } catch { $null }
}

function Get-InfoEquipo {
    try {
        $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Fabricante = $cs.Manufacturer
            Modelo     = $cs.Model
            Serial     = $bios.SerialNumber
        }
    } catch { $null }
}

# --- Panel de Inicio: resumen en vivo del equipo ---
function Actualizar-PanelInicio {
    try {
        $cpuInfo = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
        $cpuPct = if ($cpuInfo) { [math]::Round($cpuInfo.PercentProcessorTime) } else { $null }
        $window.FindName("TxtInicioCPU").Text = if ($null -ne $cpuPct) { "$cpuPct%" } else { "N/D" }
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $ramLibreGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $ramUsadaGB = [math]::Round($ramTotalGB - $ramLibreGB, 1)
        $ramPct = if ($os.TotalVisibleMemorySize -gt 0) { [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100) } else { 0 }
        $window.FindName("TxtInicioRAM").Text = "$ramPct%"

        $tiempoActivo = (Get-Date) - $os.LastBootUpTime
        $window.FindName("TxtInicioUptime").Text = "{0}d {1}h {2}m" -f $tiempoActivo.Days, $tiempoActivo.Hours, $tiempoActivo.Minutes

        $window.FindName("TxtInicioSistema").Text = "$($os.Caption) (Build $($os.BuildNumber)) | RAM: $ramUsadaGB GB usados de $ramTotalGB GB"
    } catch {}

    try {
        $discoC = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        if ($discoC -and $discoC.Size -gt 0) {
            $pctUsado = [math]::Round((($discoC.Size - $discoC.FreeSpace) / $discoC.Size) * 100)
            $window.FindName("TxtInicioDisco").Text = "$pctUsado%"
        }
    } catch {}
}

function Get-InfoCompleta {
    # Recolecta TODOS los datos visibles del equipo: modelo, numero de serie,
    # CPU, RAM, discos, placa madre, BIOS, GPU(s), red y Windows.
    $lineas = New-Object System.Collections.Generic.List[string]
    try {
        $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        $bb   = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
        $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cpu  = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $ram  = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        $discos = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
        $volumenes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
        $redes = Get-CimInstance Win32_NetworkAdapter -Filter "PhysicalAdapter=True" -ErrorAction SilentlyContinue
        $monitores = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
        $gpus = Get-InfoGPU

        $lineas.Add("=== EQUIPO ===")
        $lineas.Add("Fabricante: $($cs.Manufacturer)")
        $lineas.Add("Modelo: $($cs.Model)")
        $lineas.Add("Nombre del equipo (hostname): $($cs.Name)")
        $lineas.Add("Numero de serie: $($bios.SerialNumber)")
        if ($cs.SystemFamily) { $lineas.Add("Familia / linea: $($cs.SystemFamily)") }
        if ($cs.SystemSKUNumber) { $lineas.Add("SKU: $($cs.SystemSKUNumber)") }
        $tipoChasis = switch ($cs.PCSystemType) { 1 {"Escritorio"} 2 {"Portatil"} 3 {"Workstation"} 4 {"Servidor de escritorio"} default {"Desconocido"} }
        $lineas.Add("Tipo de equipo: $tipoChasis")
        $lineas.Add("")

        $lineas.Add("=== PROCESADOR (CPU) ===")
        $lineas.Add("Modelo: $($cpu.Name)".Trim())
        $lineas.Add("Nucleos fisicos: $($cpu.NumberOfCores) | Hilos logicos: $($cpu.NumberOfLogicalProcessors)")
        $lineas.Add("Velocidad maxima: $($cpu.MaxClockSpeed) MHz")
        $lineas.Add("")

        $lineas.Add("=== MEMORIA RAM ===")
        if ($ram) {
            $totalGB = [math]::Round((($ram | Measure-Object -Property Capacity -Sum).Sum) / 1GB, 1)
            $lineas.Add("Total instalado: $totalGB GB en $($ram.Count) modulo(s)")
            foreach ($m in $ram) {
                $capGB = [math]::Round($m.Capacity / 1GB, 1)
                $lineas.Add(" - $capGB GB, $($m.Speed) MHz, $($m.Manufacturer) (slot $($m.DeviceLocator))")
            }
        } else {
            $lineas.Add("No se pudo leer el detalle de los modulos de RAM.")
        }
        $lineas.Add("")

        $lineas.Add("=== PLACA MADRE / BIOS ===")
        $lineas.Add("Fabricante placa: $($bb.Manufacturer)")
        $lineas.Add("Modelo placa: $($bb.Product)")
        if ($bb.PartNumber) { $lineas.Add("Part Number placa: $($bb.PartNumber)") }
        if ($bb.SerialNumber) { $lineas.Add("Numero de serie placa: $($bb.SerialNumber)") }
        $lineas.Add("Fabricante BIOS: $($bios.Manufacturer)")
        $lineas.Add("Version de BIOS: $($bios.SMBIOSBIOSVersion)")
        if ($bios.ReleaseDate) { $lineas.Add("Fecha de BIOS: $($bios.ReleaseDate.ToString('yyyy-MM-dd'))") }
        $lineas.Add("")

        $lineas.Add("=== TARJETA(S) DE VIDEO ===")
        if ($gpus -and $gpus.Count -gt 0) {
            foreach ($g in $gpus) { $lineas.Add("$($g.Nombre) [$($g.Fabricante)] - Driver instalado: $($g.DriverVersion)") }
        } else {
            $lineas.Add("No se detecto ninguna GPU.")
        }
        $lineas.Add("")

        $lineas.Add("=== ALMACENAMIENTO ===")
        if ($discos) {
            foreach ($d in $discos) {
                $tamGB = [math]::Round($d.Size / 1GB, 1)
                $lineas.Add(" - $($d.Model) | $tamGB GB | Interfaz: $($d.InterfaceType)")
            }
        }
        foreach ($v in $volumenes) {
            $libreGB = [math]::Round($v.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($v.Size / 1GB, 1)
            $lineas.Add(" - Unidad $($v.DeviceID) $totalGB GB total, $libreGB GB libres ($($v.FileSystem))")
        }
        $lineas.Add("")

        if ($monitores) {
            $lineas.Add("=== MONITOR(ES) ===")
            foreach ($mon in $monitores) {
                $nombre = -join ($mon.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                if ($nombre) { $lineas.Add(" - $nombre") }
            }
            $lineas.Add("")
        }

        if ($redes) {
            $lineas.Add("=== RED ===")
            foreach ($r in $redes) {
                if ($r.MACAddress) { $lineas.Add(" - $($r.Name) | MAC: $($r.MACAddress)") }
            }
            $lineas.Add("")
        }

        $lineas.Add("=== WINDOWS ===")
        $lineas.Add("Version: $($os.Caption) - Build $($os.BuildNumber) ($($os.Version))")
        $lineas.Add("Arquitectura: $($os.OSArchitecture)")
        if ($os.InstallDate) { $lineas.Add("Fecha de instalacion: $($os.InstallDate.ToString('yyyy-MM-dd'))") }
        if ($os.SerialNumber) { $lineas.Add("ID de producto de Windows: $($os.SerialNumber)") }
        try {
            $lic = Get-CimInstance -Query "SELECT * FROM SoftwareLicensingService" -ErrorAction Stop
            if ($lic.OA3xOriginalProductKey) {
                $lineas.Add("Clave de producto (OEM/BIOS): $($lic.OA3xOriginalProductKey)")
            } else {
                $lineas.Add("Clave de producto (OEM/BIOS): no disponible (activacion digital o no incluida en BIOS)")
            }
        } catch {
            $lineas.Add("Clave de producto (OEM/BIOS): no se pudo consultar")
        }
    } catch {
        $lineas.Add("Ocurrio un error obteniendo algunos datos: $($_.Exception.Message)")
    }
    return ($lineas -join "`r`n")
}

# ---------------------------------------------------------------------------
#  NAVEGADOR INTEGRADO REAL (Microsoft Edge WebView2)
# ---------------------------------------------------------------------------
# El control WebBrowser clasico de .NET usa el motor de Internet Explorer y no
# puede renderizar sitios modernos (NVIDIA, AMD, Intel, HP, Dell, etc. son
# aplicaciones web con JavaScript moderno). La unica forma de mostrar esas
# paginas DENTRO de esta misma ventana, sin abrir un navegador externo, es
# usando el mismo motor que usa Microsoft Edge: WebView2. Sus componentes no
# vienen incluidos en PowerShell, asi que la primera vez que abras el programa
# se descargan automaticamente (una sola vez, unos 10-15 MB desde nuget.org).

$Script:WebView2Dir = Join-Path $Script:ScriptDir "WebView2Runtime"
$Script:WebView2Disponible = $false

function Ensure-WebView2Assemblies {
    $dllCore = Join-Path $Script:WebView2Dir "Microsoft.Web.WebView2.Core.dll"
    $dllForms = Join-Path $Script:WebView2Dir "Microsoft.Web.WebView2.WinForms.dll"
    $dllLoader = Join-Path $Script:WebView2Dir "WebView2Loader.dll"
    if ((Test-Path $dllCore) -and (Test-Path $dllForms) -and (Test-Path $dllLoader)) { return $true }

    try {
        Write-Log "Preparando el navegador integrado (WebView2). Solo ocurre la primera vez..." -Tipo INFO
        if (-not (Test-Path $Script:WebView2Dir)) { New-Item -Path $Script:WebView2Dir -ItemType Directory -Force | Out-Null }

        $nupkgPath = Join-Path $env:TEMP "webview2_pkg.zip"
        $urlNuget = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2"
        Invoke-WebRequest -Uri $urlNuget -OutFile $nupkgPath -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop

        $extractTmp = Join-Path $env:TEMP "webview2_pkg_extract"
        if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $nupkgPath -DestinationPath $extractTmp -Force

        $libDir = Get-ChildItem -Path (Join-Path $extractTmp "lib") -Directory | Select-Object -First 1
        Copy-Item (Join-Path $libDir.FullName "Microsoft.Web.WebView2.Core.dll") $dllCore -Force
        Copy-Item (Join-Path $libDir.FullName "Microsoft.Web.WebView2.WinForms.dll") $dllForms -Force

        $arch = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
        $loaderOrigen = Join-Path $extractTmp "runtimes\win-$arch\native\WebView2Loader.dll"
        Copy-Item $loaderOrigen $dllLoader -Force

        Remove-Item $nupkgPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Navegador integrado (WebView2) preparado correctamente." -Tipo OK
        return $true
    } catch {
        Write-Log "No se pudo descargar el navegador integrado (WebView2): $($_.Exception.Message)" -Tipo ERROR
        Write-Log "Verifica tu conexion a internet (se necesita acceso a nuget.org una sola vez) y vuelve a abrir el programa." -Tipo AVISO
        return $false
    }
}

if (Ensure-WebView2Assemblies) {
    try {
        $env:PATH = "$Script:WebView2Dir;$env:PATH"
        Add-Type -Path (Join-Path $Script:WebView2Dir "Microsoft.Web.WebView2.Core.dll")
        Add-Type -Path (Join-Path $Script:WebView2Dir "Microsoft.Web.WebView2.WinForms.dll")
        $Script:WebView2Disponible = $true
    } catch {
        Write-Log "No se pudieron cargar los componentes de WebView2: $($_.Exception.Message)" -Tipo ERROR
    }
}

function New-NavegadorEmbebido {
    param($ContenedorBorder, [string]$UrlRespaldo = $null)
    if (-not $Script:WebView2Disponible) {
        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.Text = "El navegador integrado no esta disponible (revisa el registro de actividad). Reinicia el programa con conexion a internet."
        $txt.Foreground = [System.Windows.Media.Brushes]::Orange
        $txt.TextWrapping = "Wrap"
        $txt.Margin = "16"
        $ContenedorBorder.Child = $txt
        return $null
    }
    try {
        $wfHost = New-Object System.Windows.Forms.Integration.WindowsFormsHost
        $wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2

        # Cada ventana del navegador usa su propia carpeta de perfil aislada.
        # Compartir una sola carpeta entre navegadores abiertos al mismo tiempo
        # puede hacer que uno de los dos falle al inicializar (bloqueo de perfil).
        $idInstancia = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $carpetaDatos = Join-Path $Script:ScriptDir "WebView2Data\$idInstancia"
        if (-not (Test-Path $carpetaDatos)) { New-Item -Path $carpetaDatos -ItemType Directory -Force | Out-Null }

        # Limpieza en segundo plano de perfiles de sesiones anteriores (best-effort).
        try {
            $carpetaBase = Join-Path $Script:ScriptDir "WebView2Data"
            if (Test-Path $carpetaBase) {
                Get-ChildItem -Path $carpetaBase -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne $idInstancia -and $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
                    ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            }
        } catch {}

        $creationProps = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
        $creationProps.UserDataFolder = $carpetaDatos
        $wv.CreationProperties = $creationProps

        $wfHost.Child = $wv
        $ContenedorBorder.Child = $wfHost

        $wv.Add_CoreWebView2InitializationCompleted({
            param($s, $e)
            if ($e.IsSuccess) {
                try {
                    $carpetaDescargas = Join-Path $Script:ScriptDir "Drivers"
                    if (-not (Test-Path $carpetaDescargas)) { New-Item -Path $carpetaDescargas -ItemType Directory -Force | Out-Null }
                    $wv.CoreWebView2.add_DownloadStarting({
                        param($s2, $e2)
                        $nombre = Split-Path $e2.ResultFilePath -Leaf
                        $e2.ResultFilePath = Join-Path $carpetaDescargas $nombre
                        Write-Log "Descargando dentro del programa: $nombre" -Tipo OK
                    }.GetNewClosure())
                } catch {}

                # Si la pagina principal responde con un error HTTP (403, 404, 5xx...),
                # redirige automaticamente a la URL de respaldo (Google con el ID de
                # hardware, o la busqueda mas adecuada segun el contexto). Se usa
                # NavigationCompleted + HttpStatusCode, mas simple y fiable que filtrar
                # por tipo de recurso.
                if ($UrlRespaldo) {
                    $Script:_yaRedirigioRespaldo = $false
                    try {
                        $wv.CoreWebView2.add_NavigationCompleted({
                            param($s4, $e4)
                            try {
                                $status = $null
                                try { $status = $e4.HttpStatusCode } catch { $status = $null }
                                if (-not $Script:_yaRedirigioRespaldo -and $status -and $status -ge 400) {
                                    $Script:_yaRedirigioRespaldo = $true
                                    Write-Log "La pagina respondio con error HTTP $status. Redirigiendo a una busqueda alternativa..." -Tipo AVISO
                                    $wv.CoreWebView2.Navigate($UrlRespaldo)
                                }
                            } catch {}
                        }.GetNewClosure())
                    } catch {}
                }
            } else {
                Write-Log "No se pudo iniciar el motor del navegador integrado." -Tipo ERROR
            }
        }.GetNewClosure())
        $wv.EnsureCoreWebView2Async($null) | Out-Null
        return $wv
    } catch {
        Write-Log "No se pudo crear el navegador integrado: $($_.Exception.Message)" -Tipo ERROR
        return $null
    }
}

function Global:Navegar-A {
    param($Browser, [string]$Url)
    if (-not $Browser) {
        Write-Log "El navegador integrado no esta disponible; no se puede mostrar: $Url" -Tipo ERROR
        return
    }
    try {
        $Browser.Source = New-Object Uri($Url)
        Write-Log "Abriendo dentro del programa: $Url" -Tipo INFO
    } catch {
        Write-Log "No se pudo abrir la pagina: $($_.Exception.Message)" -Tipo ERROR
    }
}

# Construye una URL de busqueda en Google como respaldo, usando de preferencia
# el ID de hardware exacto del controlador (mas preciso que el nombre).
function Global:Get-UrlRespaldoBusqueda {
    param([string]$Texto)
    $q = [uri]::EscapeDataString("$Texto driver download")
    return "https://www.google.com/search?q=$q"
}

# Abre una ventana emergente propia con el navegador integrado (WebView2)
# navegado directamente a la URL indicada. Se usa cada vez que se busca un
# controlador, en vez de compartir un navegador embebido dentro de una pestaña.
# Si la pagina principal devuelve un error HTTP (ej. 403 Forbidden, comun en
# sitios que bloquean navegadores automatizados), se redirige sola a una
# busqueda de respaldo en Google en vez de mostrar la pagina de error.
function Show-VentanaNavegador {
    param([string]$Url, [string]$Titulo = "Navegador - The Dragon Tool", [string]$TextoRespaldo = $null)
    [xml]$xamlNav = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Titulo" Height="760" Width="1080" WindowStartupLocation="CenterScreen" Background="White">
  <Window.Resources>
    <!-- Mismo efecto neon del panel lateral: boton redondeado, semitransparente, borde con degradado giratorio -->
    <LinearGradientBrush x:Key="NeonBrushNav" StartPoint="0,0" EndPoint="0.5,0.5" SpreadMethod="Repeat">
      <LinearGradientBrush.RelativeTransform>
        <TranslateTransform X="0" Y="0"/>
      </LinearGradientBrush.RelativeTransform>
      <GradientStop Color="#1F6BFF" Offset="0"/>
      <GradientStop Color="#4FA8FF" Offset="0.25"/>
      <GradientStop Color="#FFFFFF" Offset="0.5"/>
      <GradientStop Color="#4FA8FF" Offset="0.75"/>
      <GradientStop Color="#1F6BFF" Offset="1"/>
    </LinearGradientBrush>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#33141C30"/>
      <Setter Property="Foreground" Value="#EAF0FA"/>
      <Setter Property="BorderThickness" Value="1.5"/>
      <Setter Property="Height" Value="38"/>
      <Setter Property="Padding" Value="12,0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="Halo" Margin="3" CornerRadius="14" Background="#00B7FF" Opacity="0.22">
                <Border.Effect>
                  <BlurEffect Radius="10"/>
                </Border.Effect>
              </Border>
              <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{DynamicResource NeonBrushNav}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14" SnapsToDevicePixels="True">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}" RecognizesAccessKey="False"/>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#552F7CF6"/>
                <Setter TargetName="Halo" Property="Opacity" Value="0.65"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#5500E5FF"/>
                <Setter TargetName="Halo" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
                <Setter TargetName="Halo" Property="Opacity" Value="0.05"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#10141D" Padding="10,8">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="BtnVolverVentana" Content="⬅  Volver" Width="110" Margin="0,0,14,0"/>
        <Button x:Name="BtnNavRecargar" Content="🔄 Recargar" Width="110" Margin="0,0,6,0"/>
        <Button x:Name="BtnNavGoogle" Content="🔍 Buscar en Google" Width="150" Margin="0,0,6,0"/>
        <Button x:Name="BtnNavExterno" Content="🌍 Abrir en navegador externo" Width="200" Margin="0,0,6,0"/>
      </StackPanel>
    </Border>
    <Border x:Name="BrowserPopupContenedor"/>
  </DockPanel>
</Window>
"@
    $readerNav = New-Object System.Xml.XmlNodeReader $xamlNav
    $winNav = [Windows.Markup.XamlReader]::Load($readerNav)
    Iniciar-EfectosNeon -Ventana $winNav
    # (el giro del borde neon de este navegador usa su propio pincel NeonBrushNav)
    try {
        $pincelNav = $winNav.FindResource("NeonBrushNav")
        [void](Animar-PincelNeon -Pincel $pincelNav)
    } catch { }
    $urlRespaldo = if ($TextoRespaldo) { Get-UrlRespaldoBusqueda -Texto $TextoRespaldo } else { $null }
    $browserLocal = New-NavegadorEmbebido -ContenedorBorder $winNav.FindName("BrowserPopupContenedor") -UrlRespaldo $urlRespaldo

    $winNav.FindName("BtnNavRecargar").Add_Click({
        Navegar-A -Browser $browserLocal -Url $Url
    }.GetNewClosure())
    $winNav.FindName("BtnNavGoogle").Add_Click({
        if ($urlRespaldo) {
            Navegar-A -Browser $browserLocal -Url $urlRespaldo
        } else {
            Show-Aviso "No hay una busqueda de respaldo disponible para esta pagina." "Sin respaldo"
        }
    }.GetNewClosure())
    $winNav.FindName("BtnNavExterno").Add_Click({
        try {
            Start-Process $Url
            Write-Log "Pagina abierta en el navegador externo predeterminado." -Tipo OK
        } catch {
            Write-Log "No se pudo abrir el navegador externo: $($_.Exception.Message)" -Tipo ERROR
        }
    }.GetNewClosure())

    $winNav.Show()
    Navegar-A -Browser $browserLocal -Url $Url
}

# ---------------------------------------------------------------------------
#  PROGRAMAS: instalar (catalogo via winget) y desinstalar (con limpieza profunda)
# ---------------------------------------------------------------------------

function Test-WingetDisponible {
    try { $null = Get-Command winget.exe -ErrorAction Stop; return $true } catch { return $false }
}

# --- Microsoft Store: instalar directo desde un enlace, sin buscar ---
# winget (Instalador de aplicaciones de Windows) puede instalar cualquier app
# de la Microsoft Store si se le da su ID exacto (el codigo de 12 caracteres
# que aparece en la URL de la pagina de la app, ej. apps.microsoft.com/detail/9NKSQGP7F2NH).
# Esto evita depender de "winget search", que interpreta texto de consola y
# puede fallar segun el equipo.

function Get-IdDesdeLinkStore {
    param([string]$Entrada)
    if ([string]::IsNullOrWhiteSpace($Entrada)) { return $null }
    $texto = $Entrada.Trim()
    if ($texto -match '([A-Za-z0-9]{12})') {
        return $Matches[1].ToUpper()
    }
    return $null
}

function Global:Accion-InstalarDesdeLinkStore {
    param([string]$Entrada)
    $id = Get-IdDesdeLinkStore -Entrada $Entrada
    if (-not $id) {
        Show-Aviso "No se pudo identificar el ID de la app en ese texto.`n`nPega el enlace completo de la pagina de la app (apps.microsoft.com/detail/XXXXXXXXXXXX) o el codigo de 12 caracteres directamente." "No se pudo identificar la app"
        return
    }
    if (-not (Test-WingetDisponible)) {
        Show-Aviso "No se encontro 'winget' (Instalador de aplicaciones de Windows) en este equipo." "Winget no disponible"
        return
    }
    if (-not (Show-Confirm "Se instalara la app con ID '$id' directamente desde la Microsoft Store (sin abrir la app Tienda). ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Instalando app de la Microsoft Store"
    Update-VentanaProgreso -Ventana $prog -Porcentaje 15 -Estado "Descargando e instalando..." -LogLinea "Instalando ID '$id' desde la Microsoft Store..."
    try {
        $argumentos = @("install", "--id", $id, "--source", "msstore", "--exact", "--silent",
                        "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
        $procInfo = Start-Process -FilePath "winget.exe" -ArgumentList $argumentos -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($procInfo.ExitCode -eq 0) {
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "Instalado correctamente."
            Write-Log "App '$id' instalada desde la Microsoft Store." -Tipo OK
            Show-Aviso "La app se instalo correctamente." "Instalacion completada"
        } else {
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "No se pudo instalar."
            Write-Log "No se pudo instalar la app '$id' desde la Microsoft Store (codigo $($procInfo.ExitCode))." -Tipo ERROR
            Show-Aviso "No se pudo instalar la app (codigo $($procInfo.ExitCode)).`n`nVerifica que el enlace/ID sea correcto, o instalala manualmente desde la pagina web." "No se pudo instalar"
        }
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error durante la instalacion."
        Write-Log "Error al instalar la app '$id': $($_.Exception.Message)" -Tipo ERROR
    }
}


# Catalogo de programas. Se instalan a traves de winget (Instalador de
# aplicaciones de Windows, incluido en Windows 10/11), que descarga cada
# programa directamente de una fuente verificada. Algunos requieren cuenta
# o licencia propia del fabricante para activarse despues de instalados; el
# catalogo los descarga, pero no puede proporcionar la
# licencia.
$Script:CatalogoProgramas = @(
    @{ Categoria='Navegadores'; Nombre='Google Chrome'; WingetId='Google.Chrome' },
    @{ Categoria='Navegadores'; Nombre='Mozilla Firefox'; WingetId='Mozilla.Firefox' },
    @{ Categoria='Navegadores'; Nombre='Brave'; WingetId='BraveSoftware.BraveBrowser' },
    @{ Categoria='Navegadores'; Nombre='Opera'; WingetId='Opera.Opera' },
    @{ Categoria='Navegadores'; Nombre='Vivaldi'; WingetId='VivaldiTechnologies.Vivaldi' },
    @{ Categoria='Navegadores'; Nombre='Tor Browser'; WingetId='TorProject.TorBrowser' },

    @{ Categoria='Ofimatica'; Nombre='Microsoft 365 / Office'; WingetId='Microsoft.Office' },
    @{ Categoria='Ofimatica'; Nombre='LibreOffice'; WingetId='TheDocumentFoundation.LibreOffice' },
    @{ Categoria='Ofimatica'; Nombre='WPS Office'; WingetId='Kingsoft.WPSOffice' },
    @{ Categoria='Ofimatica'; Nombre='OnlyOffice Desktop Editors'; WingetId='ONLYOFFICE.DesktopEditors' },
    @{ Categoria='Ofimatica'; Nombre='Adobe Acrobat Reader DC'; WingetId='Adobe.Acrobat.Reader.64-bit' },
    @{ Categoria='Ofimatica'; Nombre='Foxit PDF Reader'; WingetId='Foxit.FoxitReader' },

    @{ Categoria='Multimedia'; Nombre='VLC Media Player'; WingetId='VideoLAN.VLC' },
    @{ Categoria='Multimedia'; Nombre='K-Lite Codec Pack (Basic)'; WingetId='CodecGuide.K-LiteCodecPack.Basic' },
    @{ Categoria='Multimedia'; Nombre='K-Lite Codec Pack (Standard)'; WingetId='CodecGuide.K-LiteCodecPack.Standard' },
    @{ Categoria='Multimedia'; Nombre='K-Lite Codec Pack (Full)'; WingetId='CodecGuide.K-LiteCodecPack.Full' },
    @{ Categoria='Multimedia'; Nombre='K-Lite Codec Pack (Mega)'; WingetId='CodecGuide.K-LiteCodecPack.Mega' },
    @{ Categoria='Multimedia'; Nombre='FFmpeg (codecs y herramientas multimedia)'; WingetId='Gyan.FFmpeg' },
    @{ Categoria='Multimedia'; Nombre='Spotify'; WingetId='Spotify.Spotify' },
    @{ Categoria='Multimedia'; Nombre='Audacity'; WingetId='Audacity.Audacity' },
    @{ Categoria='Multimedia'; Nombre='foobar2000'; WingetId='PeterPawlowski.foobar2000' },
    @{ Categoria='Multimedia'; Nombre='Media Player Classic (MPC-HC)'; WingetId='clsid2.mpc-hc' },
    @{ Categoria='Multimedia'; Nombre='HandBrake (conversor de video)'; WingetId='HandBrake.HandBrake' },
    @{ Categoria='Multimedia'; Nombre='OBS Studio (grabacion/streaming)'; WingetId='OBSProject.OBSStudio' },
    @{ Categoria='Multimedia'; Nombre='iTunes'; WingetId='Apple.iTunes' },

    @{ Categoria='Seguridad'; Nombre='Malwarebytes'; WingetId='Malwarebytes.Malwarebytes' },
    @{ Categoria='Seguridad'; Nombre='Avast Free Antivirus'; WingetId='Avast.AvastFreeAntivirus' },
    @{ Categoria='Seguridad'; Nombre='AVG AntiVirus Free'; WingetId='AVG.AVGAntiVirusFree' },
    @{ Categoria='Seguridad'; Nombre='ESET NOD32 Antivirus'; WingetId='ESET.ESETNOD32Antivirus' },
    @{ Categoria='Seguridad'; Nombre='Bitdefender Antivirus Free'; WingetId='Bitdefender.Bitdefender' },
    @{ Categoria='Seguridad'; Nombre='CCleaner'; WingetId='Piriform.CCleaner' },

    @{ Categoria='Compresion de archivos'; Nombre='7-Zip'; WingetId='7zip.7zip' },
    @{ Categoria='Compresion de archivos'; Nombre='WinRAR'; WingetId='RARLab.WinRAR' },
    @{ Categoria='Compresion de archivos'; Nombre='PeaZip'; WingetId='Giorgiotani.Peazip' },
    @{ Categoria='Compresion de archivos'; Nombre='Bandizip'; WingetId='Bandisoft.Bandizip' },

    @{ Categoria='Comunicacion'; Nombre='Zoom'; WingetId='Zoom.Zoom' },
    @{ Categoria='Comunicacion'; Nombre='Discord'; WingetId='Discord.Discord' },
    @{ Categoria='Comunicacion'; Nombre='WhatsApp'; WingetId='WhatsApp.WhatsApp' },
    @{ Categoria='Comunicacion'; Nombre='Microsoft Teams'; WingetId='Microsoft.Teams' },
    @{ Categoria='Comunicacion'; Nombre='Skype'; WingetId='Microsoft.Skype' },
    @{ Categoria='Comunicacion'; Nombre='Telegram'; WingetId='Telegram.TelegramDesktop' },
    @{ Categoria='Comunicacion'; Nombre='Signal'; WingetId='OpenWhisperSystems.Signal' },
    @{ Categoria='Comunicacion'; Nombre='Slack'; WingetId='SlackTechnologies.Slack' },
    @{ Categoria='Comunicacion'; Nombre='Mozilla Thunderbird (correo)'; WingetId='Mozilla.Thunderbird' },

    @{ Categoria='Utilidades'; Nombre='Notepad++'; WingetId='Notepad++.Notepad++' },
    @{ Categoria='Utilidades'; Nombre='Everything (buscador de archivos)'; WingetId='voidtools.Everything' },
    @{ Categoria='Utilidades'; Nombre='Microsoft PowerToys'; WingetId='Microsoft.PowerToys' },
    @{ Categoria='Utilidades'; Nombre='TeamViewer'; WingetId='TeamViewer.TeamViewer' },
    @{ Categoria='Utilidades'; Nombre='AnyDesk'; WingetId='AnyDeskSoftwareGmbH.AnyDesk' },
    @{ Categoria='Utilidades'; Nombre='Rufus (crear USB booteable)'; WingetId='Rufus.Rufus' },
    @{ Categoria='Utilidades'; Nombre='CPU-Z'; WingetId='CPUID.CPU-Z' },
    @{ Categoria='Utilidades'; Nombre='GPU-Z'; WingetId='TechPowerUp.GPU-Z' },
    @{ Categoria='Utilidades'; Nombre='HWiNFO'; WingetId='REALiX.HWiNFO' },
    @{ Categoria='Utilidades'; Nombre='CrystalDiskInfo'; WingetId='CrystalDewWorld.CrystalDiskInfo' },
    @{ Categoria='Utilidades'; Nombre='WizTree (espacio en disco)'; WingetId='AntibodySoftware.WizTree' },
    @{ Categoria='Utilidades'; Nombre='Revo Uninstaller'; WingetId='RevoUninstaller.RevoUninstaller' },
    @{ Categoria='Utilidades'; Nombre='System Informer (antes Process Hacker)'; WingetId='WinsiderSS.SystemInformer' },
    @{ Categoria='Utilidades'; Nombre='ShareX (capturas de pantalla)'; WingetId='ShareX.ShareX' },
    @{ Categoria='Utilidades'; Nombre='Ditto (historial de portapapeles)'; WingetId='Ditto.Ditto' },
    @{ Categoria='Utilidades'; Nombre='FileZilla (cliente FTP)'; WingetId='FileZilla.FileZilla' },
    @{ Categoria='Utilidades'; Nombre='Speccy (informacion del sistema)'; WingetId='Piriform.Speccy' },
    @{ Categoria='Utilidades'; Nombre='Recuva (recuperar archivos borrados)'; WingetId='Piriform.Recuva' },
    @{ Categoria='Utilidades'; Nombre='WinDirStat (espacio en disco)'; WingetId='WinDirStat.WinDirStat' },
    @{ Categoria='Utilidades'; Nombre='Windows Terminal'; WingetId='Microsoft.WindowsTerminal' },

    @{ Categoria='Diseno e ingenieria'; Nombre='GIMP'; WingetId='GIMP.GIMP' },
    @{ Categoria='Diseno e ingenieria'; Nombre='FreeCAD (CAD parametrico, sin cuenta)'; WingetId='FreeCAD.FreeCAD' },
    @{ Categoria='Diseno e ingenieria'; Nombre='LibreCAD (CAD 2D, sin cuenta)'; WingetId='LibreCAD.LibreCAD' },
    @{ Categoria='Diseno e ingenieria'; Nombre='Blender'; WingetId='BlenderFoundation.Blender' },
    @{ Categoria='Diseno e ingenieria'; Nombre='Inkscape (vectores)'; WingetId='Inkscape.Inkscape' },
    @{ Categoria='Diseno e ingenieria'; Nombre='Krita (dibujo digital)'; WingetId='KDE.Krita' },
    @{ Categoria='Diseno e ingenieria'; Nombre='Paint.NET'; WingetId='dotPDNLLC.paint.net' },
    @{ Categoria='Diseno e ingenieria'; Nombre='DaVinci Resolve (edicion de video)'; WingetId='BlackmagicDesign.DaVinciResolve' },

    @{ Categoria='Desarrollo y runtimes'; Nombre='Visual Studio Code'; WingetId='Microsoft.VisualStudioCode' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Git'; WingetId='Git.Git' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Python 3'; WingetId='Python.Python.3.12' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Java (Eclipse Temurin 17)'; WingetId='EclipseAdoptium.Temurin.17.JDK' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='.NET Desktop Runtime 8'; WingetId='Microsoft.DotNet.DesktopRuntime.8' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Visual C++ Redistributable'; WingetId='Microsoft.VCRedist.2015+.x64' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Node.js'; WingetId='OpenJS.NodeJS' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Docker Desktop'; WingetId='Docker.DockerDesktop' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Postman'; WingetId='Postman.Postman' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='MySQL Workbench'; WingetId='Oracle.MySQLWorkbench' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='Android Studio'; WingetId='Google.AndroidStudio' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='IntelliJ IDEA Community'; WingetId='JetBrains.IntelliJIDEA.Community' },
    @{ Categoria='Desarrollo y runtimes'; Nombre='PyCharm Community'; WingetId='JetBrains.PyCharm.Community' },

    @{ Categoria='Descargas'; Nombre='qBittorrent'; WingetId='qBittorrent.qBittorrent' },
    @{ Categoria='Descargas'; Nombre='Free Download Manager'; WingetId='FreeDownloadManager.FreeDownloadManager' },
    @{ Categoria='Descargas'; Nombre='JDownloader'; WingetId='AppWork.JDownloader' },

    @{ Categoria='Almacenamiento en la nube'; Nombre='Google Drive'; WingetId='Google.GoogleDrive' },
    @{ Categoria='Almacenamiento en la nube'; Nombre='Dropbox'; WingetId='Dropbox.Dropbox' },
    @{ Categoria='Almacenamiento en la nube'; Nombre='MEGA'; WingetId='Mega.MEGASync' },

    @{ Categoria='Juegos y launchers'; Nombre='Steam'; WingetId='Valve.Steam' },
    @{ Categoria='Juegos y launchers'; Nombre='Epic Games Launcher'; WingetId='EpicGames.EpicGamesLauncher' },
    @{ Categoria='Juegos y launchers'; Nombre='GOG Galaxy'; WingetId='GOG.Galaxy' },
    @{ Categoria='Juegos y launchers'; Nombre='Ubisoft Connect'; WingetId='Ubisoft.Connect' },
    @{ Categoria='Juegos y launchers'; Nombre='EA App'; WingetId='ElectronicArts.EADesktop' },
    @{ Categoria='Juegos y launchers'; Nombre='Battle.net'; WingetId='Blizzard.BattleNet' },
    @{ Categoria='Juegos y launchers'; Nombre='Riot Client (League of Legends / Valorant)'; WingetId='RiotGames.RiotClient' },
    @{ Categoria='Juegos y launchers'; Nombre='Minecraft Launcher'; WingetId='Mojang.MinecraftLauncher' },
    @{ Categoria='Juegos y launchers'; Nombre='Xbox (app de juegos de Microsoft)'; WingetId='Microsoft.GamingApp' },
    @{ Categoria='Juegos y launchers'; Nombre='Amazon Games'; WingetId='Amazon.Games' },
    @{ Categoria='Juegos y launchers'; Nombre='itch.io'; WingetId='ItchIo.Itch' },
    @{ Categoria='Juegos y launchers'; Nombre='Prism Launcher (mods de Minecraft)'; WingetId='PrismLauncher.PrismLauncher' },
    @{ Categoria='Juegos y launchers'; Nombre='CurseForge (gestor de mods)'; WingetId='Overwolf.CurseForge' },
    @{ Categoria='Emuladores'; Nombre='RetroArch (multi-sistema)'; WingetId='Libretro.RetroArch' },
    @{ Categoria='Emuladores'; Nombre='PCSX2 (PlayStation 2)'; WingetId='PCSX2Team.PCSX2' },
    @{ Categoria='Emuladores'; Nombre='Dolphin (GameCube / Wii)'; WingetId='DolphinEmulator.Dolphin' },
    @{ Categoria='Emuladores'; Nombre='RPCS3 (PlayStation 3)'; WingetId='RPCS3.RPCS3' },
    @{ Categoria='Emuladores'; Nombre='Cemu (Wii U)'; WingetId='Cemu.Cemu' },
    @{ Categoria='Emuladores'; Nombre='PPSSPP (PSP)'; WingetId='PPSSPPTeam.PPSSPP' },
    @{ Categoria='Emuladores'; Nombre='melonDS (Nintendo DS)'; WingetId='melonDS.melonDS' },
    @{ Categoria='Emuladores'; Nombre='DeSmuME (Nintendo DS)'; WingetId='DeSmuME.DeSmuME' },
    @{ Categoria='Emuladores'; Nombre='Project64 (Nintendo 64)'; WingetId='Project64.Project64' },
    @{ Categoria='Emuladores'; Nombre='MAME (arcade clasico)'; WingetId='MAMEDev.MAME' },
    @{ Categoria='Emuladores'; Nombre='DOSBox (juegos de MS-DOS)'; WingetId='DOSBox.DOSBox' },
    @{ Categoria='Emuladores'; Nombre='ScummVM (aventuras clasicas)'; WingetId='ScummVM.ScummVM' },
    @{ Categoria='Juegos y launchers'; Nombre='0 A.D. (juego de estrategia gratis)'; WingetId='WildfireGames.0ad' },
    @{ Categoria='Juegos y launchers'; Nombre='SuperTuxKart (juego de carreras gratis)'; WingetId='SuperTuxKart.SuperTuxKart' }
)

function Accion-InstalarCatalogoSeleccionado {
    param($Items)
    if (-not (Test-WingetDisponible)) {
        Show-Aviso "No se encontro 'winget' (Instalador de aplicaciones de Windows) en este equipo.`n`nInstalalo desde la Microsoft Store buscando 'App Installer' e intenta de nuevo." "Winget no disponible"
        return
    }
    if (-not $Items -or $Items.Count -eq 0) { Show-Aviso "No has seleccionado ningun programa." "Nada seleccionado"; return }
    if (-not (Requiere-Admin)) { return }
    if (-not (Show-Confirm "Se instalaran $($Items.Count) programa(s) seleccionados usando winget (Instalador de aplicaciones de Windows).`n`nCada uno se descarga de su fuente verificada. Puede tardar varios minutos segun tu conexion. ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Instalando programas" -PermitirDetener
    $i = 0
    $exitosos = 0
    $fallidos = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Items) {
        $i++
        if ($prog.Tag -eq $true) {
            Write-Log "Instalacion de programas cancelada por el usuario." -Tipo AVISO
            break
        }
        $pct = [math]::Round(($i / $Items.Count) * 100)
        Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Instalando $($item.Nombre) ($i de $($Items.Count))..." -LogLinea "Instalando $($item.Nombre) [$($item.WingetId)]..."

        try {
            $argumentos = @("install", "--id", $item.WingetId, "-e", "--silent",
                            "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
            $procInfo = Start-Process -FilePath "winget.exe" -ArgumentList $argumentos -Wait -PassThru -NoNewWindow -ErrorAction Stop
            if ($procInfo.ExitCode -eq 0) {
                $exitosos++
                Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "$($item.Nombre) instalado correctamente."
            } else {
                $fallidos.Add($item.Nombre) | Out-Null
                Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "No se pudo instalar $($item.Nombre) (codigo $($procInfo.ExitCode))."
            }
        } catch {
            $fallidos.Add($item.Nombre) | Out-Null
            Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "Error instalando $($item.Nombre): $($_.Exception.Message)"
        }
    }

    Close-VentanaProgreso -Ventana $prog -MensajeFinal "$exitosos de $($Items.Count) instalado(s)."
    Write-Log "Instalacion de programas finalizada: $exitosos exitoso(s), $($fallidos.Count) fallido(s)." -Tipo OK
    if ($fallidos.Count -gt 0) {
        Show-Aviso "$exitosos programa(s) instalado(s) correctamente.`n`nNo se pudieron instalar: $($fallidos -join ', ')" "Instalacion finalizada"
    } else {
        Show-Aviso "Los $exitosos programa(s) seleccionados se instalaron correctamente." "Instalacion finalizada"
    }
}

# --- Desinstalar programas con limpieza profunda de rastros ---

function Get-ProgramasInstalados {
    $rutas = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $todos = foreach ($patron in $rutas) {
        Get-ItemProperty -Path $patron -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -and $_.DisplayName.Trim() -ne '' -and -not $_.SystemComponent -and -not $_.ParentKeyName
        } | ForEach-Object {
            [PSCustomObject]@{
                Nombre       = $_.DisplayName
                Publicador   = "$($_.Publisher)"
                Version      = "$($_.DisplayVersion)"
                UninstallStr = "$($_.UninstallString)"
                InstallLoc   = "$($_.InstallLocation)"
                RegistryPath = $_.PSPath
            }
        }
    }
    $agrupado = $todos | Group-Object Nombre | ForEach-Object { $_.Group | Select-Object -First 1 }
    return $agrupado | Sort-Object Nombre
}

# Elimina archivos y entradas residuales de un programa: carpeta de
# instalacion (si quedo alguna), carpetas de datos en AppData/ProgramData,
# accesos directos del menu inicio, y la clave de registro de desinstalacion.
function Limpiar-RastrosPrograma {
    param([string]$Nombre, [string]$InstallLoc, $RegistryPath)

    if ($InstallLoc -and (Test-Path -LiteralPath $InstallLoc -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $InstallLoc -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    # Lista de nombres de carpeta que NUNCA se deben borrar aunque coincidan,
    # para evitar borrar por error datos compartidos de otro programa (p.ej.
    # desinstalar algo llamado "Drive" o "One" no debe tocar OneDrive).
    $carpetasProtegidas = @(
        'OneDrive','Google','Microsoft','Windows','Windows NT','Common Files','Packages',
        'SystemApps','WindowsApps','Program Files','Program Files (x86)','ProgramData',
        'Temp','Temporary Internet Files','Default','Public','All Users'
    )
    $nombreCarpeta = ($Nombre -replace '[\\/:*?"<>|]', '').Trim()
    if ($nombreCarpeta -and $nombreCarpeta.Length -ge 3) {
        foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData, "$env:ProgramFiles", "${env:ProgramFiles(x86)}")) {
            if (-not $base) { continue }
            # Coincidencia EXACTA de nombre de carpeta (sin comodines): un
            # filtro por subcadena aqui podria borrar carpetas de otros
            # programas que simplemente contengan el mismo texto (p.ej.
            # desinstalar "Mail" borraria "OneDrive Mail Sync" por error).
            Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ieq $nombreCarpeta -and ($carpetasProtegidas -notcontains $_.Name) } |
                ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
        }
        foreach ($baseMenu in @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
            if (-not (Test-Path -LiteralPath $baseMenu)) { continue }
            Get-ChildItem -Path $baseMenu -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -ieq $nombreCarpeta -or $_.Name -ieq $nombreCarpeta } |
                ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
        }
    }

    if ($RegistryPath -and (Test-Path $RegistryPath)) {
        try { Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Accion-DesinstalarPrograma {
    param($Item, [switch]$Forzar)
    if (-not $Item) { Show-Aviso "Selecciona un programa de la lista." "Sin seleccion"; return }
    if (-not (Requiere-Admin)) { return }

    $textoAccion = if ($Forzar) { "FORZAR la desinstalacion de" } else { "desinstalar" }
    $advertenciaForzar = if ($Forzar) { "`n`nEl modo forzado NO ejecuta el desinstalador del programa: elimina directamente sus archivos y su entrada del registro. Usalo solo si la desinstalacion normal ha fallado." } else { "" }
    if (-not (Show-Confirm "Se va a $textoAccion '$($Item.Nombre)', eliminando tambien archivos y entradas residuales (menu inicio, AppData, ProgramData, clave de desinstalacion) para no dejar rastro.$advertenciaForzar`n`nEsta accion no se puede deshacer. ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Desinstalando: $($Item.Nombre)"
    try {
        if (-not $Forzar -and $Item.UninstallStr) {
            Update-VentanaProgreso -Ventana $prog -Porcentaje 15 -Estado "Ejecutando el desinstalador de $($Item.Nombre)..." -LogLinea "Comando de desinstalacion: $($Item.UninstallStr)"
            try {
                if ($Item.UninstallStr -match 'msiexec') {
                    $coincidenciaGuid = [regex]::Match($Item.UninstallStr, '\{[0-9A-Fa-f-]+\}')
                    if ($coincidenciaGuid.Success) {
                        Start-Process -FilePath "msiexec.exe" -ArgumentList @("/x", $coincidenciaGuid.Value, "/quiet", "/norestart") -Wait -ErrorAction Stop
                    } else {
                        Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $Item.UninstallStr) -Wait -ErrorAction Stop
                    }
                } elseif ($Item.UninstallStr -match '^\s*"([^"]+)"\s*(.*)$') {
                    Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -Wait -ErrorAction Stop
                } else {
                    Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $Item.UninstallStr) -Wait -ErrorAction Stop
                }
                Update-VentanaProgreso -Ventana $prog -Porcentaje 60 -Estado "Desinstalador finalizado. Limpiando rastros..." -LogLinea "Desinstalador ejecutado."
            } catch {
                Update-VentanaProgreso -Ventana $prog -Porcentaje 60 -Estado "El desinstalador no se pudo ejecutar. Limpiando rastros de todas formas..." -LogLinea "No se pudo ejecutar el desinstalador normalmente: $($_.Exception.Message)"
            }
        } elseif ($Forzar) {
            Update-VentanaProgreso -Ventana $prog -Porcentaje 30 -Estado "Forzando eliminacion (sin ejecutar desinstalador)..." -LogLinea "Modo forzado: eliminando archivos y registro directamente."
        } else {
            Update-VentanaProgreso -Ventana $prog -Porcentaje 30 -Estado "No hay desinstalador registrado. Limpiando directamente..." -LogLinea "No se encontro un comando de desinstalacion; se limpiara directamente."
        }

        Update-VentanaProgreso -Ventana $prog -Porcentaje 80 -Estado "Eliminando archivos y entradas residuales (AppData, ProgramData, menu inicio, registro)..."
        Limpiar-RastrosPrograma -Nombre $Item.Nombre -InstallLoc $Item.InstallLoc -RegistryPath $Item.RegistryPath

        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Desinstalacion completada."
        Write-Log "'$($Item.Nombre)' desinstalado y sus rastros fueron limpiados." -Tipo OK
        Show-Aviso "'$($Item.Nombre)' fue desinstalado y se limpiaron sus archivos y entradas residuales." "Desinstalacion completada"
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Error durante la desinstalacion."
        Write-Log "Error al desinstalar '$($Item.Nombre)': $($_.Exception.Message)" -Tipo ERROR
    }
}

# Ventana con la lista de programas instalados y los botones de desinstalar sin dejar
# rastros / forzar desinstalacion. Se abre al instante y carga la lista despues.
function Show-VentanaProgramasInstalados {
    [xml]$xamlProgs = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Programas instalados - The Dragon Tool" Height="660" Width="1000"
        WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)
$($Global:RecursosGridXaml)
  </Window.Resources>
  <DockPanel Margin="14">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Foreground="White" TextWrapping="Wrap" Margin="0,0,0,8"
               Text="Selecciona un programa y elige como quitarlo. 'Sin dejar rastros' ejecuta su desinstalador y despues borra archivos, datos y registro sobrantes. 'Forzar' NO usa el desinstalador: borra directamente (usalo solo si la forma normal fallo)."/>
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <TextBlock Text="🔍" VerticalAlignment="Center" Margin="0,0,8,0" FontSize="14"/>
      <TextBox x:Name="TxtProgBuscar" MaxWidth="460" HorizontalAlignment="Left"/>
    </DockPanel>
    <TextBlock x:Name="TxtProgResumen" DockPanel.Dock="Top" Foreground="#66AEFF" FontWeight="Bold" Margin="0,0,0,8" Text="Cargando programas instalados..."/>
    <WrapPanel DockPanel.Dock="Bottom" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnProgActualizar" Content="🔄 Actualizar lista" Width="160" Margin="0,0,8,0"/>
      <Button x:Name="BtnProgDesinstalar" Content="🗑️ Desinstalar sin dejar rastros" Width="250" Margin="0,0,8,0" FontWeight="Bold"/>
      <Button x:Name="BtnProgForzar" Content="💥 Forzar desinstalacion" Width="210" Margin="0,0,8,0" FontWeight="Bold"/>
      <Button x:Name="BtnProgCerrar" Content="Cerrar" Width="100"/>
    </WrapPanel>
    <DataGrid x:Name="GridProgInst" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single" SelectionUnit="FullRow"
              Background="#151B27" RowBackground="#151B27" AlternatingRowBackground="#1C2635" Foreground="White"
              BorderBrush="#232B3D" HorizontalGridLinesBrush="#232B3D" VerticalGridLinesBrush="#232B3D" RowHeaderWidth="0"
              CanUserAddRows="False" HeadersVisibility="Column">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Programa" Binding="{Binding Nombre}" Width="2.4*"/>
        <DataGridTextColumn Header="Publicador" Binding="{Binding Publicador}" Width="1.5*"/>
        <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
"@
    $readerProgs = New-Object System.Xml.XmlNodeReader $xamlProgs
    $win = [Windows.Markup.XamlReader]::Load($readerProgs)
    Iniciar-EfectosNeon -Ventana $win
    $grid = $win.FindName("GridProgInst")
    $txtResumen = $win.FindName("TxtProgResumen")
    $txtBuscar = $win.FindName("TxtProgBuscar")
    $est = @{ Todos = @(); Cargado = $false }

    $mostrarFiltrado = {
        $texto = $txtBuscar.Text
        if ([string]::IsNullOrWhiteSpace($texto)) {
            $grid.ItemsSource = @($est.Todos)
            $txtResumen.Text = "Total: $(@($est.Todos).Count) programa(s) instalado(s)."
        } else {
            $patron = [regex]::Escape($texto.Trim())
            $filtrados = @($est.Todos | Where-Object { $_.Nombre -match $patron -or $_.Publicador -match $patron })
            $grid.ItemsSource = $filtrados
            $txtResumen.Text = "Mostrando $($filtrados.Count) de $(@($est.Todos).Count) programa(s)."
        }
    }
    $cargarLista = {
        $txtResumen.Text = "Cargando programas instalados..."
        Wait-UI -Milisegundos 1
        $est.Todos = @(Get-ProgramasInstalados)
        $est.Cargado = $true
        & $mostrarFiltrado
    }

    $win.Add_ContentRendered({
        if (-not $est.Cargado) { & $cargarLista }
    })
    $txtBuscar.Add_TextChanged({ if ($est.Cargado) { & $mostrarFiltrado } })
    $win.FindName("BtnProgActualizar").Add_Click({ & $cargarLista })
    $win.FindName("BtnProgCerrar").Add_Click({ $win.Close() })
    $win.FindName("BtnProgDesinstalar").Add_Click({
        $sel = $grid.SelectedItem
        if (-not $sel) { Show-Aviso "Selecciona un programa de la lista." "Sin seleccion"; return }
        Accion-DesinstalarPrograma -Item $sel
        & $cargarLista
    })
    $win.FindName("BtnProgForzar").Add_Click({
        $sel = $grid.SelectedItem
        if (-not $sel) { Show-Aviso "Selecciona un programa de la lista." "Sin seleccion"; return }
        Accion-DesinstalarPrograma -Item $sel -Forzar
        & $cargarLista
    })
    $win.ShowDialog() | Out-Null
}

# ---------------------------------------------------------------------------
#  QUITAR APPS DE WINDOWS (apps de la tienda: AppX/MSIX), incluida Microsoft Store
# ---------------------------------------------------------------------------
# Tabla de apps conocidas: patron del nombre interno -> nombre amigable, nivel y nota.
# Niveles: Recomendada (publicidad/relleno), Opcional (utiles segun el gusto),
#          Precaucion (algo puede dejar de funcionar), Importante (Windows o este programa la usan).
$Script:CatalogoAppsWindows = @(
    @{ P='^Microsoft\.WindowsStore$';                 N='Microsoft Store';                     V='Precaucion'; T='Sin la Store no podras instalar ni actualizar apps de la tienda. Se puede reinstalar con: wsreset -i' },
    @{ P='^Microsoft\.StorePurchaseApp$';             N='Compras de Microsoft Store';          V='Precaucion'; T='Componente de pagos de la Store.' },
    @{ P='^Microsoft\.DesktopAppInstaller$';          N='Instalador de aplicaciones (winget)'; V='Importante'; T='Este programa usa winget para instalar apps: quitarlo rompe esa funcion.' },
    @{ P='^Microsoft\.SecHealthUI$';                  N='Seguridad de Windows';                V='Importante'; T='Interfaz de Windows Defender.' },
    @{ P='^Microsoft\.Windows\.(ShellExperienceHost|StartMenuExperienceHost|Search|CloudExperienceHost)$|^MicrosoftWindows\.Client\.'; N='Componente del sistema'; V='Importante'; T='Parte de la interfaz de Windows.' },
    @{ P='^Microsoft\.(WindowsTerminal|WindowsTerminalPreview)$'; N='Terminal de Windows';  V='Precaucion'; T='Terminal moderna de Windows 11.' },
    @{ P='^Microsoft\.(HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebpImageExtension|WebMediaExtensions|RawImageExtension|AV1VideoExtension|MPEG2VideoExtension)'; N='Extension de codec de imagen/video'; V='Precaucion'; T='Sin ella algunos formatos de foto o video no se abren.' },
    @{ P='^Microsoft\.(Xbox\.TCUI|XboxIdentityProvider|XboxGameCallableUI)$'; N='Servicios de Xbox'; V='Precaucion'; T='Necesarios para iniciar sesion en juegos de Xbox / Game Pass.' },
    @{ P='^Microsoft\.(GamingApp|XboxApp)$';          N='Xbox';                                V='Opcional';   T='App de Xbox / Game Pass.' },
    @{ P='^Microsoft\.XboxGamingOverlay$|^Microsoft\.XboxGameOverlay$|^Microsoft\.XboxSpeechToTextOverlay$'; N='Barra de juegos de Xbox'; V='Opcional'; T='Superposicion de juegos (Win+G).' },
    @{ P='^Microsoft\.549981C3F5F10$';                N='Cortana';                             V='Recomendada'; T='Asistente en desuso.' },
    @{ P='^Microsoft\.BingNews$';                     N='Noticias (MSN)';                      V='Recomendada'; T='' },
    @{ P='^Microsoft\.BingWeather$';                  N='El Tiempo (MSN)';                     V='Recomendada'; T='' },
    @{ P='^Microsoft\.Bing(Finance|Sports|Search|Translator|Travel|Food|Health)';  N='Aplicacion de Bing'; V='Recomendada'; T='' },
    @{ P='^Microsoft\.GetHelp$';                      N='Obtener ayuda';                       V='Recomendada'; T='' },
    @{ P='^Microsoft\.Getstarted$';                   N='Sugerencias / Tips';                  V='Recomendada'; T='' },
    @{ P='^Microsoft\.Microsoft3DViewer$';            N='Visor 3D';                            V='Recomendada'; T='' },
    @{ P='^Microsoft\.MixedReality\.Portal$';         N='Portal de realidad mixta';            V='Recomendada'; T='' },
    @{ P='^Microsoft\.MicrosoftOfficeHub$';           N='Microsoft 365 (Office)';              V='Recomendada'; T='Acceso directo/publicidad de Office.' },
    @{ P='^Microsoft\.MicrosoftSolitaireCollection$'; N='Solitario';                           V='Recomendada'; T='' },
    @{ P='^Microsoft\.Office\.OneNote$';              N='OneNote';                             V='Opcional';   T='' },
    @{ P='^Microsoft\.People$';                       N='Contactos';                           V='Recomendada'; T='' },
    @{ P='^Microsoft\.SkypeApp$';                     N='Skype';                               V='Recomendada'; T='' },
    @{ P='^Microsoft\.Wallet$';                       N='Microsoft Pay / Cartera';             V='Recomendada'; T='' },
    @{ P='^Microsoft\.WindowsFeedbackHub$';           N='Centro de opiniones';                 V='Recomendada'; T='' },
    @{ P='^Microsoft\.WindowsMaps$';                  N='Mapas';                               V='Opcional';   T='' },
    @{ P='^Microsoft\.ZuneMusic$';                    N='Reproductor multimedia / Groove';     V='Opcional';   T='' },
    @{ P='^Microsoft\.ZuneVideo$';                    N='Peliculas y TV';                      V='Opcional';   T='' },
    @{ P='^Microsoft\.YourPhone$|^MicrosoftWindows\.CrossDevice$'; N='Vincular con el movil';  V='Recomendada'; T='' },
    @{ P='^microsoft\.windowscommunicationsapps$';    N='Correo y Calendario';                 V='Opcional';   T='' },
    @{ P='^Microsoft\.Todos$';                        N='Microsoft To Do';                     V='Recomendada'; T='' },
    @{ P='^Microsoft\.PowerAutomateDesktop$';         N='Power Automate';                      V='Recomendada'; T='' },
    @{ P='^Microsoft\.OutlookForWindows$';            N='Outlook (nuevo)';                     V='Opcional';   T='' },
    @{ P='^Microsoft\.MicrosoftStickyNotes$';         N='Notas rapidas';                       V='Opcional';   T='' },
    @{ P='^Microsoft\.MSPaint$';                      N='Paint 3D';                            V='Recomendada'; T='' },
    @{ P='^Microsoft\.Paint$';                        N='Paint';                               V='Opcional';   T='' },
    @{ P='^Microsoft\.Windows\.Photos$';              N='Fotos';                               V='Opcional';   T='Visor de imagenes por defecto.' },
    @{ P='^Microsoft\.WindowsCalculator$';            N='Calculadora';                         V='Opcional';   T='' },
    @{ P='^Microsoft\.WindowsAlarms$';                N='Alarmas y reloj';                     V='Opcional';   T='' },
    @{ P='^Microsoft\.WindowsCamera$';                N='Camara';                              V='Opcional';   T='' },
    @{ P='^Microsoft\.WindowsSoundRecorder$';         N='Grabadora de sonidos';                V='Opcional';   T='' },
    @{ P='^Microsoft\.ScreenSketch$';                 N='Recortes (Snipping Tool)';            V='Opcional';   T='' },
    @{ P='^Microsoft\.WindowsNotepad$';               N='Bloc de notas';                       V='Opcional';   T='' },
    @{ P='^Microsoft\.Windows\.DevHome$';             N='Dev Home';                            V='Recomendada'; T='' },
    @{ P='^MicrosoftCorporationII\.QuickAssist$';     N='Asistencia rapida';                   V='Opcional';   T='' },
    @{ P='^MicrosoftCorporationII\.MicrosoftFamily$'; N='Microsoft Family';                    V='Recomendada'; T='' },
    @{ P='^MicrosoftTeams$|^MSTeams$';                N='Microsoft Teams (personal)';          V='Recomendada'; T='' },
    @{ P='^Clipchamp\.Clipchamp$';                    N='Clipchamp (editor de video)';         V='Recomendada'; T='' },
    @{ P='^Microsoft\.MicrosoftEdge';                 N='Microsoft Edge (componente)';         V='Precaucion'; T='' },
    @{ P='^Microsoft\.Copilot$|^Microsoft\.Windows\.Ai\.Copilot';  N='Copilot';                V='Recomendada'; T='' },
    @{ P='^Microsoft\.LinkedIn$|LinkedIn';            N='LinkedIn';                            V='Recomendada'; T='' }
)

# Apps de terceros que suelen venir con drivers de la marca (audio, graficos...): mejor no quitarlas a ciegas.
$Script:PatronAppsDeMarca = 'Realtek|NVIDIA|Intel|AMD|Dolby|Waves|Nahimic|DTS|Dell|HP|Lenovo|ASUS|Acer|MSI|Alienware|Razer|Logitech|Samsung|Toshiba|Huawei|Honor|Xiaomi|Qualcomm|MediaTek|Broadcom|Synaptics|Elan|Goodix|Sonic|Bang'

function Get-ClasificacionAppWindows {
    param([string]$Nombre, [string]$Editor)
    foreach ($regla in $Script:CatalogoAppsWindows) {
        if ($Nombre -match $regla.P) { return @{ Nombre = $regla.N; Nivel = $regla.V; Nota = $regla.T } }
    }
    $amigable = ($Nombre -replace '^(Microsoft|MicrosoftCorporationII|MicrosoftWindows|Windows)\.', '' -replace '^[A-F0-9]{8,}\.', '')
    if ($Nombre -match '^(Microsoft|MicrosoftCorporationII|MicrosoftWindows|Windows)\.|^microsoft\.') {
        return @{ Nombre = $amigable; Nivel = 'Opcional'; Nota = 'App de Microsoft.' }
    }
    if ($Nombre -match $Script:PatronAppsDeMarca -or $Editor -match $Script:PatronAppsDeMarca) {
        return @{ Nombre = $amigable; Nivel = 'Precaucion'; Nota = 'App de la marca del equipo (puede controlar audio, pantalla o drivers).' }
    }
    return @{ Nombre = $amigable; Nivel = 'Recomendada'; Nota = 'App de terceros preinstalada o descargada de la tienda.' }
}

# Lista las apps de Windows que SI se pueden quitar (sin componentes del sistema ni librerias).
function Get-AppsWindows {
    $paquetes = @()
    try { $paquetes = @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
    catch { try { $paquetes = @(Get-AppxPackage -ErrorAction Stop) } catch { $paquetes = @() } }

    $utiles = @($paquetes | Where-Object {
        -not $_.IsFramework -and -not $_.IsResourcePackage -and $_.NonRemovable -ne $true -and "$($_.SignatureKind)" -ne 'System'
    })
    $resultado = New-Object System.Collections.Generic.List[object]
    foreach ($grupo in ($utiles | Group-Object Name)) {
        $primero = $grupo.Group | Select-Object -First 1
        $editor = "$($primero.Publisher)" -replace '^CN=([^,]+).*$', '$1'
        $clas = Get-ClasificacionAppWindows -Nombre $grupo.Name -Editor $editor
        $iconoNivel = switch ($clas.Nivel) { 'Recomendada' { '🟢 Recomendada' } 'Opcional' { '🟡 Opcional' } 'Precaucion' { '🟠 Precaucion' } default { '🔴 Importante' } }
        $resultado.Add([PSCustomObject]@{
            Nombre      = $clas.Nombre
            Nivel       = $iconoNivel
            NivelClave  = $clas.Nivel
            Nota        = $clas.Nota
            Version     = "$($primero.Version)"
            Editor      = $editor
            NombreAppx  = $grupo.Name
            Paquetes    = @($grupo.Group | ForEach-Object { $_.PackageFullName })
        })
    }
    return @($resultado | Sort-Object @{ Expression = { switch ($_.NivelClave) { 'Recomendada' { 0 } 'Opcional' { 1 } 'Precaucion' { 2 } default { 3 } } } }, Nombre)
}

# Quita las apps elegidas (con barra de progreso). Devuelve las quitadas y las que fallaron.
function Remove-AppsWindowsSeleccionadas {
    param($Items, [bool]$QuitarPrecargadas = $true)
    $quitadas = New-Object System.Collections.Generic.List[object]
    $fallidas = New-Object System.Collections.Generic.List[string]
    $prog = New-VentanaProgreso -Titulo "Quitando apps de Windows" -PermitirDetener
    $total = @($Items).Count
    $i = 0
    foreach ($item in $Items) {
        $i++
        if ($prog.Tag -eq $true) { Write-Log "Quitar apps de Windows: detenido por el usuario." -Tipo AVISO; break }
        $pct = [math]::Round((($i - 1) / [math]::Max($total, 1)) * 100)
        Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Quitando $($item.Nombre) ($i de $total)..." -LogLinea "Quitando $($item.Nombre) [$($item.NombreAppx)]..."
        $huboError = $false
        foreach ($completo in $item.Paquetes) {
            try {
                Remove-AppxPackage -Package $completo -AllUsers -ErrorAction Stop
            } catch {
                try { Remove-AppxPackage -Package $completo -ErrorAction Stop }
                catch {
                    $huboError = $true
                    Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -LogLinea "  No se pudo quitar $completo : $($_.Exception.Message)"
                }
            }
        }
        if ($QuitarPrecargadas -and -not $huboError) {
            try {
                Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $item.NombreAppx } |
                    ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
            } catch {}
        }
        if ($huboError) { $fallidas.Add($item.Nombre) | Out-Null }
        else {
            $quitadas.Add($item) | Out-Null
            Update-VentanaProgreso -Ventana $prog -Porcentaje ([math]::Round(($i / [math]::Max($total, 1)) * 100)) -LogLinea "  $($item.Nombre) quitada."
        }
    }
    Close-VentanaProgreso -Ventana $prog -MensajeFinal "$($quitadas.Count) de $total app(s) quitada(s)."
    # Registro de lo quitado, por si quieres volver a instalar alguna
    $rutaRegistro = $null
    if ($quitadas.Count -gt 0) {
        try {
            $carpeta = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'DragonTool_AppsQuitadas'
            if (-not (Test-Path $carpeta)) { New-Item -ItemType Directory -Path $carpeta -Force | Out-Null }
            $rutaRegistro = Join-Path $carpeta ("AppsQuitadas_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            $lineas = @("Apps de Windows quitadas con The Dragon Tool - $(Get-Date)", "Para reinstalar una: Microsoft Store (buscala por nombre) o: winget install `"<nombre>`"", "")
            foreach ($q in $quitadas) { $lineas += "$($q.Nombre)  [$($q.NombreAppx)]  v$($q.Version)" }
            $lineas | Set-Content -Path $rutaRegistro -Encoding UTF8
        } catch { $rutaRegistro = $null }
    }
    return @{ Quitadas = $quitadas; Fallidas = $fallidas; Registro = $rutaRegistro }
}

function Show-VentanaAppsWindows {
    if (-not (Requiere-Admin)) { return }
    [xml]$xamlApps = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Quitar apps de Windows - The Dragon Tool" Height="680" Width="1080"
        WindowStartupLocation="CenterScreen" Background="#10141D">
  <Window.Resources>$($Global:RecursosNeonXaml)
$($Global:RecursosGridXaml)
  </Window.Resources>
  <DockPanel Margin="14">
    <Button x:Name="BtnVolverVentana" DockPanel.Dock="Top" Content="⬅  Volver" Width="110" Height="34" HorizontalAlignment="Left" Margin="0,0,0,10"/>
    <TextBlock DockPanel.Dock="Top" Foreground="White" TextWrapping="Wrap" Margin="0,0,0,6"
               Text="Marca las apps que quieras quitar (Ctrl o Mayus + clic para elegir varias). 🟢 Recomendada = relleno o publicidad · 🟡 Opcional = util segun tu gusto · 🟠 Precaucion = algo puede dejar de funcionar (incluye Microsoft Store) · 🔴 Importante = Windows o este programa la usan."/>
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,6">
      <TextBlock Text="🔍" VerticalAlignment="Center" Margin="0,0,8,0" FontSize="14"/>
      <TextBox x:Name="TxtAppsBuscar" MaxWidth="460" HorizontalAlignment="Left"/>
    </DockPanel>
    <TextBlock x:Name="TxtAppsResumen" DockPanel.Dock="Top" Foreground="#66AEFF" FontWeight="Bold" Margin="0,0,0,8" Text="Cargando apps instaladas (puede tardar unos segundos)..."/>
    <CheckBox x:Name="ChkAppsPrecargadas" DockPanel.Dock="Bottom" Foreground="White" Margin="0,8,0,0" IsChecked="True"
              Content="Quitar tambien del perfil base de Windows (para que no vuelvan en usuarios nuevos ni tras actualizar)"/>
    <WrapPanel DockPanel.Dock="Bottom" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnAppsRecomendadas" Content="Seleccionar recomendadas" Width="210" Margin="0,0,8,0"/>
      <Button x:Name="BtnAppsTodo" Content="Seleccionar todo" Width="150" Margin="0,0,8,0"/>
      <Button x:Name="BtnAppsNinguno" Content="Quitar seleccion" Width="150" Margin="0,0,8,0"/>
      <Button x:Name="BtnAppsQuitar" Content="🗑️ Quitar seleccionadas" Width="220" Margin="0,0,8,0" FontWeight="Bold"/>
      <Button x:Name="BtnAppsCerrar" Content="Cerrar" Width="100"/>
    </WrapPanel>
    <DataGrid x:Name="GridApps" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Extended" SelectionUnit="FullRow"
              Background="#151B27" RowBackground="#151B27" AlternatingRowBackground="#1C2635" Foreground="White"
              BorderBrush="#232B3D" HorizontalGridLinesBrush="#232B3D" VerticalGridLinesBrush="#232B3D" RowHeaderWidth="0"
              CanUserAddRows="False" HeadersVisibility="Column">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Aplicacion" Binding="{Binding Nombre}" Width="2*"/>
        <DataGridTextColumn Header="Nivel" Binding="{Binding Nivel}" Width="140"/>
        <DataGridTextColumn Header="Nota" Binding="{Binding Nota}" Width="3*"/>
        <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="120"/>
        <DataGridTextColumn Header="Editor" Binding="{Binding Editor}" Width="1.3*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
"@
    $readerApps = New-Object System.Xml.XmlNodeReader $xamlApps
    $win = [Windows.Markup.XamlReader]::Load($readerApps)
    Iniciar-EfectosNeon -Ventana $win
    $grid = $win.FindName("GridApps")
    $txtResumen = $win.FindName("TxtAppsResumen")
    $txtBuscar = $win.FindName("TxtAppsBuscar")
    $chkPre = $win.FindName("ChkAppsPrecargadas")
    $est = @{ Todas = @(); Cargado = $false }

    $mostrar = {
        $texto = $txtBuscar.Text
        $vista = @($est.Todas)
        if (-not [string]::IsNullOrWhiteSpace($texto)) {
            $patron = [regex]::Escape($texto.Trim())
            $vista = @($vista | Where-Object { $_.Nombre -match $patron -or $_.NombreAppx -match $patron -or $_.Editor -match $patron })
        }
        $grid.ItemsSource = $vista
        $rec = @($est.Todas | Where-Object { $_.NivelClave -eq 'Recomendada' }).Count
        $txtResumen.Text = "Apps encontradas: $(@($est.Todas).Count)   |   Recomendadas para quitar: $rec   |   Mostrando: $($vista.Count)"
    }
    $cargar = {
        $txtResumen.Text = "Cargando apps instaladas (puede tardar unos segundos)..."
        Wait-UI -Milisegundos 1
        $est.Todas = @(Get-AppsWindows)
        $est.Cargado = $true
        & $mostrar
    }
    $win.Add_ContentRendered({ if (-not $est.Cargado) { & $cargar } })
    $txtBuscar.Add_TextChanged({ if ($est.Cargado) { & $mostrar } })
    $win.FindName("BtnAppsTodo").Add_Click({ $grid.SelectAll() })
    $win.FindName("BtnAppsNinguno").Add_Click({ $grid.UnselectAll() })
    $win.FindName("BtnAppsRecomendadas").Add_Click({
        $grid.UnselectAll()
        foreach ($elemento in @($grid.ItemsSource)) {
            if ($elemento.NivelClave -eq 'Recomendada') { [void]$grid.SelectedItems.Add($elemento) }
        }
    })
    $win.FindName("BtnAppsCerrar").Add_Click({ $win.Close() })
    $win.FindName("BtnAppsQuitar").Add_Click({
        $seleccion = @($grid.SelectedItems)
        if ($seleccion.Count -eq 0) {
            Show-Aviso "Selecciona primero una o mas apps de la lista (Ctrl o Mayus + clic para elegir varias)." "Sin seleccion"
            return
        }
        $mensaje = "Se van a quitar $($seleccion.Count) app(s):`n - " + (($seleccion | Select-Object -First 15 | ForEach-Object { $_.Nombre }) -join "`n - ")
        if ($seleccion.Count -gt 15) { $mensaje += "`n - ... y $($seleccion.Count - 15) mas" }
        $tieneStore = @($seleccion | Where-Object { $_.NombreAppx -match '^Microsoft\.(WindowsStore|StorePurchaseApp)$' }).Count -gt 0
        $tieneImportante = @($seleccion | Where-Object { $_.NivelClave -eq 'Importante' }).Count -gt 0
        $tienePrecaucion = @($seleccion | Where-Object { $_.NivelClave -eq 'Precaucion' }).Count -gt 0
        if ($tieneStore) { $mensaje += "`n`nIncluye Microsoft Store: sin ella no podras instalar ni actualizar apps de la tienda. Para recuperarla: wsreset -i (o reinstalar desde Configuracion > Aplicaciones)." }
        if ($tieneImportante) { $mensaje += "`n`nATENCION: hay apps marcadas como IMPORTANTE (Windows o este programa las usan). Quitarlas puede romper funciones del sistema." }
        elseif ($tienePrecaucion) { $mensaje += "`n`nHay apps marcadas con PRECAUCION: algo podria dejar de funcionar si las necesitas." }
        $mensaje += "`n`nSe guardara un registro de lo quitado en Documentos. ¿Continuar?"
        if (-not (Show-Confirm $mensaje "Quitar apps de Windows")) { return }
        if ($tieneImportante) {
            if (-not (Show-Confirm "Hay apps IMPORTANTES en la seleccion. ¿Seguro que quieres quitarlas tambien?" "Confirmar de nuevo")) { return }
        }
        $resultado = Remove-AppsWindowsSeleccionadas -Items $seleccion -QuitarPrecargadas ([bool]$chkPre.IsChecked)
        $nombresQuitados = @($resultado.Quitadas | ForEach-Object { $_.NombreAppx })
        $est.Todas = @($est.Todas | Where-Object { $nombresQuitados -notcontains $_.NombreAppx })
        & $mostrar
        Write-Log "Apps de Windows quitadas: $($resultado.Quitadas.Count) de $($seleccion.Count)." -Tipo OK
        $texto = "Apps quitadas: $($resultado.Quitadas.Count) de $($seleccion.Count)."
        if ($resultado.Registro) { $texto += "`n`nRegistro guardado en:`n$($resultado.Registro)" }
        if ($resultado.Fallidas.Count -gt 0) { $texto += "`n`nNo se pudieron quitar:`n - " + ($resultado.Fallidas -join "`n - ") }
        Show-Aviso $texto "Resultado"
    })
    $win.ShowDialog() | Out-Null
}

# --- Archivos ISO: Windows y Office, descarga DIRECTA (sin abrir el navegador) ---
# Para Windows 11 y 10 se automatiza el mismo proceso oficial en 3 pasos que
# usa la pagina de Microsoft (elegir edicion -> elegir idioma -> obtener el
# enlace real de descarga), pero por codigo en vez de clics: el archivo sigue
# viniendo directo de los servidores de Microsoft, solo que sin mostrar
# ninguna ventana de navegador. Para Office se descarga directamente el
# instalador oficial de la Herramienta de implementacion de Office (ODT).
# Las versiones donde este proceso automatico no aplica de forma confiable
# (Windows 7/8.1, ediciones de evaluacion) usan el navegador integrado como
# respaldo, para no arriesgar una descarga incorrecta.
$Script:CatalogoISO = @{
    'Windows' = @(
        @{ Nombre = 'Windows 11'; Modo = 'DirectoWindows'; Segmento = 'windows11'; Extension = 'iso' },
        @{ Nombre = 'Windows 10'; Modo = 'DirectoWindows'; Segmento = 'windows10'; Extension = 'iso' },
        @{ Nombre = 'Windows 8.1'; Modo = 'Navegador'; Url = 'https://www.microsoft.com/software-download/windows8ISO' },
        @{ Nombre = 'Windows 7'; Modo = 'Navegador'; Url = 'https://www.microsoft.com/en-us/software-download/windows7' },
        @{ Nombre = 'Windows 11 Enterprise (evaluacion)'; Modo = 'Navegador'; Url = 'https://www.microsoft.com/evalcenter/evaluate-windows-11-enterprise' },
        @{ Nombre = 'Windows 10 Enterprise (evaluacion)'; Modo = 'Navegador'; Url = 'https://www.microsoft.com/evalcenter/evaluate-windows-10-enterprise' },
        @{ Nombre = 'Windows Server 2022 (evaluacion)'; Modo = 'Navegador'; Url = 'https://www.microsoft.com/evalcenter/evaluate-windows-server-2022' },
        @{ Nombre = 'Windows Server 2019 (evaluacion)'; Modo = 'Navegador'; Url = 'https://www.microsoft.com/evalcenter/evaluate-windows-server-2019' }
    )
    'Office' = @(
        @{ Nombre = 'Herramienta de implementacion de Office (ODT) - descarga directa'; Modo = 'DirectoArchivo'; UrlPagina = 'https://www.microsoft.com/en-us/download/details.aspx?id=49117'; Patron = 'https://download\.microsoft\.com/download/[^"'']+officedeploymenttool[^"'']+\.exe'; Extension = 'exe' },
        @{ Nombre = 'Microsoft 365 / Office (pagina oficial)'; Modo = 'Navegador'; Url = 'https://www.office.com/' },
        @{ Nombre = 'Comparar todas las versiones de Office'; Modo = 'Navegador'; Url = 'https://www.microsoft.com/en-us/microsoft-365/buy/compare-all-microsoft-365-products' }
    )
    'Linux' = @(
        @{ Nombre = 'Ubuntu Desktop (LTS)'; Modo = 'DirectoArchivo'; UrlPagina = 'https://releases.ubuntu.com/24.04/'; Patron = 'ubuntu-24\.04[\d.]*-desktop-amd64\.iso'; Extension = 'iso' },
        @{ Nombre = 'Debian (netinst)'; Modo = 'DirectoArchivo'; UrlPagina = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/'; Patron = 'debian-[\d.]+-amd64-netinst\.iso'; Extension = 'iso' },
        @{ Nombre = 'Linux Mint'; Modo = 'Navegador'; Url = 'https://linuxmint.com/download.php' },
        @{ Nombre = 'Fedora Workstation'; Modo = 'Navegador'; Url = 'https://fedoraproject.org/workstation/download' },
        @{ Nombre = 'Manjaro'; Modo = 'Navegador'; Url = 'https://manjaro.org/download/' },
        @{ Nombre = 'Pop!_OS'; Modo = 'Navegador'; Url = 'https://pop.system76.com/' },
        @{ Nombre = 'Zorin OS'; Modo = 'Navegador'; Url = 'https://zorin.com/os/download/' },
        @{ Nombre = 'elementary OS'; Modo = 'Navegador'; Url = 'https://elementary.io/' },
        @{ Nombre = 'Kali Linux'; Modo = 'Navegador'; Url = 'https://www.kali.org/get-kali/' },
        @{ Nombre = 'openSUSE'; Modo = 'Navegador'; Url = 'https://get.opensuse.org/' },
        @{ Nombre = 'Arch Linux'; Modo = 'Navegador'; Url = 'https://archlinux.org/download/' },
        @{ Nombre = 'Rocky Linux'; Modo = 'Navegador'; Url = 'https://rockylinux.org/download' },
        @{ Nombre = 'AlmaLinux'; Modo = 'Navegador'; Url = 'https://almalinux.org/get-almalinux/' },
        @{ Nombre = 'MX Linux'; Modo = 'Navegador'; Url = 'https://mxlinux.org/download-links/' },
        @{ Nombre = 'Solus'; Modo = 'Navegador'; Url = 'https://getsol.us/download/' },
        @{ Nombre = 'EndeavourOS'; Modo = 'Navegador'; Url = 'https://endeavouros.com/latest-release/' },
        @{ Nombre = 'Garuda Linux'; Modo = 'Navegador'; Url = 'https://garudalinux.org/downloads' },
        @{ Nombre = 'Linux Lite'; Modo = 'Navegador'; Url = 'https://www.linuxliteos.com/download.php' },
        @{ Nombre = 'CentOS Stream'; Modo = 'Navegador'; Url = 'https://www.centos.org/centos-stream/' }
    )
}
$Script:IdiomasISO = @('Español (se elige durante la instalacion)', 'Ingles (se elige durante la instalacion)', 'Multiidioma / no aplica')

$Script:UserAgentDescarga = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

# Automatiza el proceso oficial de 3 pasos de microsoft.com/software-download
# para obtener el enlace real y temporal del archivo .iso (mismo mecanismo
# que usa la pagina web, sin abrir ningun navegador).
function Get-EnlaceDescargaWindowsISO {
    param([string]$Segmento)

    $sessionId = [guid]::NewGuid().ToString()
    $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $encabezados = @{ "User-Agent" = $Script:UserAgentDescarga }

    Invoke-WebRequest -Uri "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sessionId" `
        -Headers $encabezados -WebSession $webSession -UseBasicParsing -ErrorAction Stop -TimeoutSec 30 | Out-Null

    $urlPagina = "https://www.microsoft.com/en-us/software-download/$Segmento"
    $pagina = Invoke-WebRequest -Uri $urlPagina -Headers $encabezados -WebSession $webSession -UseBasicParsing -ErrorAction Stop -TimeoutSec 30
    $encabezados["Referer"] = $urlPagina

    $coincidenciaEdicion = [regex]::Match($pagina.Content, 'option value="(\d+)"')
    if (-not $coincidenciaEdicion.Success) { throw "Microsoft no devolvio ninguna edicion disponible para $Segmento (puede haber cambiado su pagina)." }
    $productEditionId = $coincidenciaEdicion.Groups[1].Value

    $urlSkus = "https://www.microsoft.com/en-us/api/controls/contentinclude/html?pageId=6e2a1789-ef16-4f27-a296-74ef7ef5d96b&host=www.microsoft.com&segments=software-download,$Segmento&query=&action=getskuinformationbyproductedition&sessionId=$sessionId&productEditionId=$productEditionId&sdVersion=2"
    $htmlSkus = Invoke-RestMethod -Uri $urlSkus -Headers $encabezados -WebSession $webSession -ErrorAction Stop -TimeoutSec 30
    $coincidenciaSku = [regex]::Match($htmlSkus, 'option id="(\d+)"[^>]*>\s*(English[^<]*)')
    if (-not $coincidenciaSku.Success) { $coincidenciaSku = [regex]::Match($htmlSkus, 'option id="(\d+)"') }
    if (-not $coincidenciaSku.Success) { throw "Microsoft no devolvio idiomas disponibles (puede haber cambiado su pagina)." }
    $skuId = $coincidenciaSku.Groups[1].Value
    $idioma = if ($coincidenciaSku.Groups.Count -gt 2 -and $coincidenciaSku.Groups[2].Value) { $coincidenciaSku.Groups[2].Value.Trim() } else { "English International" }

    $urlEnlace = "https://www.microsoft.com/en-us/api/controls/contentinclude/html?pageId=0f6ecde5-9760-407c-a3e9-58b41ea3d84d&host=www.microsoft.com&segments=software-download,$Segmento&query=&action=GetProductDownloadLinksBySku&sessionId=$sessionId&skuId=$skuId&language=$([uri]::EscapeDataString($idioma))&sdVersion=2"
    $htmlEnlace = Invoke-RestMethod -Uri $urlEnlace -Headers $encabezados -WebSession $webSession -ErrorAction Stop -TimeoutSec 30
    $coincidenciaUrl = [regex]::Match($htmlEnlace, 'href="([^"]+\.iso[^"]*)"')
    if (-not $coincidenciaUrl.Success) {
        throw "Microsoft no genero un enlace de descarga esta vez (a veces limita las solicitudes automatizadas; intenta de nuevo en unos minutos, o usa la pagina oficial como respaldo)."
    }
    return ($coincidenciaUrl.Groups[1].Value -replace '&amp;', '&')
}

# Descarga la pagina del Centro de descarga de Microsoft indicada y extrae el
# enlace directo del archivo segun el patron dado.
function Get-EnlaceDescargaDirecta {
    param([string]$UrlPagina, [string]$Patron)
    $pagina = Invoke-WebRequest -Uri $UrlPagina -Headers @{ "User-Agent" = $Script:UserAgentDescarga } -UseBasicParsing -ErrorAction Stop -TimeoutSec 30
    $coincidencia = [regex]::Match($pagina.Content, $Patron)
    if (-not $coincidencia.Success) { throw "No se encontro el enlace de descarga directa en la pagina (puede haber cambiado)." }
    $valor = $coincidencia.Value -replace '&amp;', '&'
    if ($valor -notmatch '^https?://') {
        # La coincidencia es un nombre de archivo relativo (ej. listado de un
        # directorio de mirror): se combina con la URL base de la pagina.
        $uriBase = New-Object System.Uri($UrlPagina)
        $valor = (New-Object System.Uri($uriBase, $valor)).AbsoluteUri
    }
    return $valor
}

# Descarga un archivo mostrando progreso real (bytes recibidos) en la ventana
# de progreso, con soporte para cancelar.
function Descargar-ArchivoConProgreso {
    param([string]$Url, [string]$RutaDestino, $VentanaProgreso, [string]$NombreArchivo)

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", $Script:UserAgentDescarga)
    $Script:_descargaISOCompleta = $false
    $Script:_descargaISOError = $null

    $wc.add_DownloadProgressChanged({
        param($s, $e)
        $mbRecibidos = [math]::Round($e.BytesReceived / 1MB, 1)
        $mbTotal = [math]::Round($e.TotalBytesToReceive / 1MB, 1)
        Update-VentanaProgreso -Ventana $VentanaProgreso -Porcentaje $e.ProgressPercentage -Estado "Descargando $NombreArchivo... ($mbRecibidos MB de $mbTotal MB)"
    }.GetNewClosure())
    $wc.add_DownloadFileCompleted({
        param($s, $e)
        if ($e.Error -and -not $e.Cancelled) { $Script:_descargaISOError = $e.Error.Message }
        $Script:_descargaISOCompleta = $true
    }.GetNewClosure())

    try {
        $wc.DownloadFileAsync([Uri]$Url, $RutaDestino)
        while (-not $Script:_descargaISOCompleta) {
            if ($VentanaProgreso.Tag -eq $true) {
                $wc.CancelAsync()
            }
            Start-Sleep -Milliseconds 100
            Wait-UI -Milisegundos 1
        }
    } finally {
        # El "finally" garantiza que el WebClient (y su socket HTTP interno)
        # se libere siempre, incluso si algo en el bucle de espera lanza una
        # excepcion - importante porque esta funcion puede ejecutarse muchas
        # veces en la misma sesion (varias descargas de ISO/Office).
        $wc.Dispose()
    }
    if ($Script:_descargaISOError) { throw $Script:_descargaISOError }
}

function Accion-DescargarISO {
    param($ItemSeleccionado)
    if (-not $ItemSeleccionado) { Show-Aviso "Selecciona una version primero." "Nada seleccionado"; return }
    $nombre = $ItemSeleccionado.Nombre

    # Las versiones sin un metodo directo confiable usan el navegador integrado como respaldo.
    if ($ItemSeleccionado.Modo -eq 'Navegador') {
        Write-Log "Abriendo la pagina oficial de descarga para: $nombre" -Tipo INFO
        Show-VentanaNavegador -Url $ItemSeleccionado.Url -Titulo "Descargar: $nombre" -TextoRespaldo "$nombre ISO download official"
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    $extension = if ($ItemSeleccionado.Extension) { $ItemSeleccionado.Extension } else { 'iso' }
    $dialogo = New-Object System.Windows.Forms.SaveFileDialog
    $dialogo.Title = "Guardar $nombre como..."
    $dialogo.Filter = "Archivo (*.$extension)|*.$extension"
    $dialogo.FileName = ($nombre -replace '[\\/:*?"<>|]', '') + ".$extension"
    $dialogo.InitialDirectory = [Environment]::GetFolderPath('UserProfile') + "\Downloads"
    if ($dialogo.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Log "Descarga de '$nombre' cancelada (no se eligio ubicacion)." -Tipo AVISO
        return
    }
    $rutaDestino = $dialogo.FileName

    if (-not (Show-Confirm "Se descargara '$nombre' directamente desde los servidores de Microsoft hacia:`n$rutaDestino`n`n¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Descargando $nombre" -PermitirDetener
    try {
        Update-VentanaProgreso -Ventana $prog -Porcentaje 3 -Estado "Consultando el enlace oficial de descarga en Microsoft..." -LogLinea "Preparando descarga de '$nombre'..."

        $urlReal = $null
        if ($ItemSeleccionado.Modo -eq 'DirectoWindows') {
            $urlReal = Get-EnlaceDescargaWindowsISO -Segmento $ItemSeleccionado.Segmento
        } elseif ($ItemSeleccionado.Modo -eq 'DirectoArchivo') {
            $urlReal = Get-EnlaceDescargaDirecta -UrlPagina $ItemSeleccionado.UrlPagina -Patron $ItemSeleccionado.Patron
        }

        Update-VentanaProgreso -Ventana $prog -Porcentaje 6 -Estado "Enlace obtenido. Iniciando descarga..." -LogLinea "Enlace de descarga obtenido correctamente."
        Descargar-ArchivoConProgreso -Url $urlReal -RutaDestino $rutaDestino -VentanaProgreso $prog -NombreArchivo $nombre

        if ($prog.Tag -eq $true) {
            Close-VentanaProgreso -Ventana $prog -MensajeFinal "Descarga cancelada."
            Write-Log "Descarga de '$nombre' cancelada por el usuario." -Tipo AVISO
            try { Remove-Item -Path $rutaDestino -Force -ErrorAction SilentlyContinue } catch {}
            return
        }

        Close-VentanaProgreso -Ventana $prog -MensajeFinal "Descarga completada."
        Write-Log "'$nombre' descargado correctamente en: $rutaDestino" -Tipo OK
        Show-Aviso "'$nombre' se descargo correctamente en:`n$rutaDestino" "Descarga completada"
    } catch {
        Close-VentanaProgreso -Ventana $prog -MensajeFinal "No se pudo completar la descarga."
        Write-Log "No se pudo descargar '$nombre': $($_.Exception.Message)" -Tipo ERROR
        if (Show-Confirm "No se pudo completar la descarga directa de '$nombre':`n$($_.Exception.Message)`n`n¿Quieres abrir la pagina oficial de Microsoft en el navegador integrado como alternativa?") {
            $urlRespaldo = if ($ItemSeleccionado.Segmento) { "https://www.microsoft.com/en-us/software-download/$($ItemSeleccionado.Segmento)" } else { $ItemSeleccionado.UrlPagina }
            Show-VentanaNavegador -Url $urlRespaldo -Titulo "Descargar: $nombre" -TextoRespaldo "$nombre ISO download official"
        }
    }
}

# --- Tarjeta de video, Placa madre y Portatil: navegacion directa ---
# Los campos de texto para "buscar por modelo" no funcionaban de forma
# confiable (cada fabricante usa su propio buscador interno con JavaScript,
# y las URLs de busqueda por texto libre no siempre devuelven resultados).
# En su lugar, cada boton abre la pagina NORMAL de descargas del fabricante,
# en una ventana emergente propia con el navegador integrado (WebView2),
# para que selecciones tu modelo ahi igual que en su sitio real.

function Buscar-DriverGPU {
    param([string]$Fabricante, [string]$ModeloDetectado = $null)
    $url = switch ($Fabricante) {
        'NVIDIA' { "https://www.nvidia.com/Download/index.aspx" }
        'AMD'    { "https://www.amd.com/en/support/download/drivers.html" }
        'Intel'  { "https://www.intel.com/content/www/us/en/download-center/home.html" }
        default  { $null }
    }
    if (-not $url) { Write-Log "Selecciona un fabricante (NVIDIA, AMD o Intel)." -Tipo AVISO; return }
    $respaldo = if ($ModeloDetectado) { "$ModeloDetectado driver" } else { "$Fabricante graphics driver" }
    Show-VentanaNavegador -Url $url -Titulo "Controladores $Fabricante" -TextoRespaldo $respaldo
}

$Script:UrlPlaca = @{
    'ASUS'       = 'https://www.asus.com/support/Download-Center/'
    'MSI'        = 'https://www.msi.com/support/download'
    'Gigabyte'   = 'https://www.gigabyte.com/Support'
    'ASRock'     = 'https://www.asrock.com/support/index.asp?cat=Down'
    'Biostar'    = 'https://www.biostar.com.tw/app/en/mb/support.php'
    'EVGA'       = 'https://www.evga.com/support/drivers/'
    'Supermicro' = 'https://www.supermicro.com/en/support/resources/downloadcenter'
}

function Buscar-DriverPlaca {
    param([string]$Marca)
    $url = $Script:UrlPlaca[$Marca]
    if (-not $url) { Write-Log "Selecciona la marca de la placa." -Tipo AVISO; return }
    Show-VentanaNavegador -Url $url -Titulo "Controladores $Marca" -TextoRespaldo "$Marca motherboard driver"
}

$Script:UrlLaptop = @{
    'HP'                = 'https://support.hp.com/us-en/drivers'
    'Dell'              = 'https://www.dell.com/support/home/en-us'
    'Lenovo'            = 'https://pcsupport.lenovo.com/us/en'
    'ASUS'              = 'https://www.asus.com/support/Download-Center/'
    'Acer'              = 'https://www.acer.com/us-en/support'
    'MSI'               = 'https://www.msi.com/support/download'
    'Samsung'           = 'https://www.samsung.com/us/support/downloadcenter/'
    'Toshiba/Dynabook'  = 'https://support.dynabook.com/'
    'Huawei'            = 'https://consumer.huawei.com/en/support/'
    'Honor'             = 'https://www.hihonor.com/global/support/'
    'LG'                = 'https://www.lg.com/us/support'
    'Microsoft Surface' = 'https://www.microsoft.com/en-us/surface/support'
    'Razer'             = 'https://www.razer.com/support'
    'Fujitsu'           = 'https://www.fujitsu.com/global/support/products/software/driver/'
    'Gigabyte / AORUS'  = 'https://www.gigabyte.com/Support'
    'Panasonic'         = 'https://na.panasonic.com/support'
    'VAIO'              = 'https://us.vaio.com/support/'
    'Medion'            = 'https://www.medion.com/en/service/start/'
    'Chuwi'             = 'https://www.chuwi.com/support'
    'Xiaomi'            = 'https://www.mi.com/global/service/'
    'Positivo'          = 'https://www.positivo.com.br/suporte/'
    'Clevo/Sager'       = 'https://www.sagernotebook.com/support/'
    'Getac'             = 'https://www.getac.com/en/support/'
    'Framework'         = 'https://knowledgebase.frame.work/'
    'NEC'               = 'https://www.support.nec.co.jp/'
}

function Buscar-DriverLaptop {
    param([string]$Fabricante)
    $url = $Script:UrlLaptop[$Fabricante]
    if (-not $url) { Write-Log "Selecciona la marca del portatil." -Tipo AVISO; return }
    Show-VentanaNavegador -Url $url -Titulo "Controladores $Fabricante" -TextoRespaldo "$Fabricante laptop driver"
}

# ---------------------------------------------------------------------------
#  INTERFAZ GRAFICA (XAML)
# ---------------------------------------------------------------------------

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="The Dragon Tool" Height="780" Width="1060"
        WindowStartupLocation="CenterScreen" Background="#0A0E14">
    <Window.Resources>

        <!-- Paleta de colores: negro / azul moderno -->
        <SolidColorBrush x:Key="BgPrincipal" Color="#0A0E14"/>
        <SolidColorBrush x:Key="BgPanel" Color="#10141D"/>
        <SolidColorBrush x:Key="BgTarjeta" Color="#151B27"/>
        <SolidColorBrush x:Key="BgTarjetaHover" Color="#1C2635"/>
        <SolidColorBrush x:Key="BgTarjetaPress" Color="#0F1520"/>
        <SolidColorBrush x:Key="Borde" Color="#232B3D"/>
        <SolidColorBrush x:Key="Acento" Color="#2F7CF6"/>
        <SolidColorBrush x:Key="AcentoClaro" Color="#5B9CFF"/>
        <SolidColorBrush x:Key="TextoPrimario" Color="#EAF0FA"/>
        <SolidColorBrush x:Key="TextoSecundario" Color="#7C93BD"/>
        <SolidColorBrush x:Key="TextoAcento" Color="#66AEFF"/>

        <!-- Pincel neon compartido: su angulo se anima desde codigo (una sola animacion mueve todos los bordes a la vez) -->
        <LinearGradientBrush x:Key="NeonBrush" StartPoint="0,0" EndPoint="0.5,0.5" SpreadMethod="Repeat">
            <LinearGradientBrush.RelativeTransform>
                <TranslateTransform X="0" Y="0"/>
            </LinearGradientBrush.RelativeTransform>
            <GradientStop Color="#1F6BFF" Offset="0"/>
            <GradientStop Color="#4FA8FF" Offset="0.25"/>
            <GradientStop Color="#FFFFFF" Offset="0.5"/>
            <GradientStop Color="#4FA8FF" Offset="0.75"/>
            <GradientStop Color="#1F6BFF" Offset="1"/>
        </LinearGradientBrush>

        <!-- Boton moderno: redondeado, semitransparente y con borde neon animado (igual que el panel lateral) -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#33141C30"/>
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="BorderThickness" Value="1.5"/>
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Grid RenderTransformOrigin="0.5,0.5">
                            <Grid.RenderTransform><ScaleTransform x:Name="Esc" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
                            <Border x:Name="Halo" Margin="3" CornerRadius="14" Background="#00B7FF" Opacity="0.18">
                                <Border.Effect>
                                    <BlurEffect Radius="10"/>
                                </Border.Effect>
                            </Border>
                            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                                    BorderBrush="{DynamicResource NeonBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="14" SnapsToDevicePixels="True">
                                <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                                   VerticalAlignment="Center" Margin="{TemplateBinding Padding}" RecognizesAccessKey="False"/>
                            </Border>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#552F7CF6"/>
                                <Setter TargetName="Halo" Property="Opacity" Value="0.65"/>
                                <Trigger.EnterActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="1.035" Duration="0:0:0.12"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="1.035" Duration="0:0:0.12"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.15"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.15"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.ExitActions>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#5500E5FF"/>
                                <Setter TargetName="Halo" Property="Opacity" Value="0.9"/>
                                <Trigger.EnterActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="0.95" Duration="0:0:0.07"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="0.95" Duration="0:0:0.07"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions>
                  <BeginStoryboard>
                    <Storyboard>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleX" To="1.035" Duration="0:0:0.12"/>
                      <DoubleAnimation Storyboard.TargetName="Esc" Storyboard.TargetProperty="ScaleY" To="1.035" Duration="0:0:0.12"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.ExitActions>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
                                <Setter TargetName="Halo" Property="Opacity" Value="0.05"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Pestañas: subrayado de acento al seleccionar -->
        <Style TargetType="TabItem">
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="{StaticResource TextoSecundario}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Bd" Background="Transparent" BorderBrush="{StaticResource Acento}" BorderThickness="0,0,0,2" Margin="0,0,4,0">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="12,8"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="BorderThickness" Value="0,0,0,2"/>
                                <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter TargetName="Bd" Property="BorderThickness" Value="0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Campos de texto y listas: plano y oscuro -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#99151B27"/>
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="BorderBrush" Value="#44509BFF"/>
            <Setter Property="BorderThickness" Value="1.5"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="CaretBrush" Value="{StaticResource AcentoClaro}"/>
            <Setter Property="SelectionBrush" Value="#552F7CF6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="Bd" CornerRadius="10" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" SnapsToDevicePixels="True">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" Focusable="False"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource NeonBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Barras de desplazamiento delgadas con pulgar neon -->
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="11"/>
      <Setter Property="Height" Value="Auto"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Border Background="#22000000" CornerRadius="5" Margin="1">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="Pulgar" CornerRadius="5" Background="#8800B7FF" BorderBrush="{DynamicResource NeonBrush}" BorderThickness="1"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Pulgar" Property="Background" Value="#CC00E5FF"/>
                          </Trigger>
                          <Trigger Property="IsDragging" Value="True">
                            <Setter TargetName="Pulgar" Property="Background" Value="#FFBFE3FF"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="Height" Value="11"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Border Background="#22000000" CornerRadius="5" Margin="1">
                  <Track x:Name="PART_Track">
                    <Track.DecreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageLeftCommand" Opacity="0" Focusable="False"/>
                    </Track.DecreaseRepeatButton>
                    <Track.IncreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageRightCommand" Opacity="0" Focusable="False"/>
                    </Track.IncreaseRepeatButton>
                    <Track.Thumb>
                      <Thumb>
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border x:Name="Pulgar" CornerRadius="5" Background="#8800B7FF" BorderBrush="{DynamicResource NeonBrush}" BorderThickness="1"/>
                            <ControlTemplate.Triggers>
                              <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Pulgar" Property="Background" Value="#CC00E5FF"/>
                              </Trigger>
                              <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="Pulgar" Property="Background" Value="#FFBFE3FF"/>
                              </Trigger>
                            </ControlTemplate.Triggers>
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                  </Track>
                </Border>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
        <SolidColorBrush x:Key="PopupFondo" Color="#151B27" Opacity="0.95"/>

        <!-- Items de la lista desplegable: fondo oscuro, texto legible, resaltado azul -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="5" Margin="4,1" SnapsToDevicePixels="True">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Acento}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource BgTarjetaHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ComboBox completo: caja cerrada + lista desplegable oscura y semitransparente -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="{StaticResource BgTarjeta}"/>
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Borde}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleBtn" Focusable="False" ClickMode="Press" Background="Transparent" BorderThickness="0"
                                          IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="ToggleBorder" Background="{StaticResource BgTarjeta}" BorderBrush="{StaticResource Borde}" BorderThickness="1" CornerRadius="8">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="26"/>
                                                </Grid.ColumnDefinitions>
                                                <Path Grid.Column="1" Data="M0,0 L5,5 L10,0 Z" Fill="{StaticResource TextoSecundario}"
                                                      HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="BorderBrush" TargetName="ToggleBorder" Value="{StaticResource Acento}"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False"
                                               Content="{TemplateBinding SelectionBoxItem}"
                                               ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                               Margin="12,0,30,0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                            <Popup x:Name="Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Border Background="{StaticResource PopupFondo}" BorderBrush="{StaticResource Acento}" BorderThickness="1" CornerRadius="8"
                                        MinWidth="{Binding ActualWidth, ElementName=ToggleBtn}" MaxHeight="280" Margin="0,4,0,0">
                                    <Border.Effect>
                                        <DropShadowEffect Color="#000000" BlurRadius="20" ShadowDepth="4" Opacity="0.55"/>
                                    </Border.Effect>
                                    <ScrollViewer Margin="3" SnapsToDevicePixels="True">
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="Margin" Value="2,3"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="Margin" Value="4"/>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="{StaticResource TextoAcento}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Borde}"/>
        </Style>

        <!-- Tarjeta de agrupacion visual (usada para reorganizar paneles) -->
        <Style x:Key="TarjetaSeccion" TargetType="Border">
            <Setter Property="Background" Value="#9910142A"/>
            <Setter Property="BorderBrush" Value="{DynamicResource NeonBrush}"/>
            <Setter Property="BorderThickness" Value="1.2"/>
            <Setter Property="CornerRadius" Value="14"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,14"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#CC14204A"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- DataGrid: tema oscuro consistente con el resto de la app -->
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="{StaticResource BgTarjeta}"/>
            <Setter Property="Foreground" Value="{StaticResource TextoAcento}"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="BorderBrush" Value="{StaticResource Borde}"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
        </Style>
        <Style TargetType="DataGridCell">
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{StaticResource Acento}"/>
                    <Setter Property="Foreground" Value="White"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="#88101420"/>
            <Setter Property="RowBackground" Value="#55101420"/>
            <Setter Property="AlternatingRowBackground" Value="#55151B27"/>
            <Setter Property="BorderBrush" Value="{DynamicResource NeonBrush}"/>
            <Setter Property="BorderThickness" Value="1.2"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource Borde}"/>
            <Setter Property="VerticalGridLinesBrush" Value="{StaticResource Borde}"/>
            <Setter Property="RowHeaderWidth" Value="0"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserResizeRows" Value="False"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="RowHeight" Value="32"/>
        </Style>

        <!-- ===== Navegacion lateral neon ===== -->
        <!-- TabControl sin franja de pestanas: la navegacion la hace el panel lateral -->
        <Style x:Key="TabSinCabecera" TargetType="TabControl">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabControl">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter ContentSource="SelectedContent"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Boton del panel lateral: redondeado, semitransparente, borde neon animado -->
        <Style x:Key="NeonNavButton" TargetType="RadioButton">
            <Setter Property="Foreground" Value="{StaticResource TextoPrimario}"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,5"/>
            <Setter Property="Height" Value="46"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Grid>
                            <Grid.RenderTransform><TranslateTransform x:Name="Desl" X="0"/></Grid.RenderTransform>
                            <Border x:Name="Halo" Margin="3" CornerRadius="14" Background="#00B7FF" Opacity="0.22">
                                <Border.Effect>
                                    <BlurEffect Radius="12"/>
                                </Border.Effect>
                            </Border>
                            <Border x:Name="Neon" CornerRadius="14" BorderThickness="1.5" BorderBrush="{DynamicResource NeonBrush}"
                                    Background="#33141C30" SnapsToDevicePixels="True">
                                <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" Margin="18,0,10,0" RecognizesAccessKey="False"/>
                            </Border>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Neon" Property="Background" Value="#552F7CF6"/>
                                <Setter TargetName="Halo" Property="Opacity" Value="0.65"/>
                                <Trigger.EnterActions>
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <DoubleAnimation Storyboard.TargetName="Desl" Storyboard.TargetProperty="X" To="9" Duration="0:0:0.14"/>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.EnterActions>
                                <Trigger.ExitActions>
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <DoubleAnimation Storyboard.TargetName="Desl" Storyboard.TargetProperty="X" To="0" Duration="0:0:0.18"/>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.ExitActions>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Neon" Property="Background" Value="#5500E5FF"/>
                                <Setter TargetName="Neon" Property="BorderThickness" Value="2.5"/>
                                <Setter TargetName="Halo" Property="Opacity" Value="0.9"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <DockPanel>
        <!-- Encabezado -->
        <Border DockPanel.Dock="Top" Background="#55141C30" BorderBrush="{DynamicResource NeonBrush}" BorderThickness="0,0,0,2" Padding="16,10">
            <StackPanel Orientation="Horizontal">
                <Image x:Name="ImgLogo" Height="56" Margin="0,0,16,0"/>
                <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="THE DRAGON TOOL" Foreground="{DynamicResource NeonBrush}" FontSize="24" FontWeight="Black">
                        <TextBlock.Effect>
                            <DropShadowEffect Color="#00B7FF" BlurRadius="16" ShadowDepth="0" Opacity="0.75"/>
                        </TextBlock.Effect>
                    </TextBlock>
                    <TextBlock Text="Creado por Adrian Barrientos" Foreground="{StaticResource TextoAcento}" FontSize="12" FontWeight="SemiBold"/>
                    <TextBlock x:Name="TxtEstadoAdmin" Text="Comprobando permisos..." Foreground="{StaticResource TextoSecundario}" FontSize="12" Margin="0,2,0,0"/>
                    <Button x:Name="BtnAbrirComoAdmin" Content="🛡️ Abrir como administrador" Height="30" Padding="10,0" FontSize="11" HorizontalAlignment="Left" BorderBrush="{StaticResource Acento}" Margin="0,6,0,0" Visibility="Collapsed"/>
                </StackPanel>
            </StackPanel>
        </Border>

        <!-- Log inferior -->
        <Border DockPanel.Dock="Bottom" Background="#55101420" BorderBrush="{DynamicResource NeonBrush}" BorderThickness="0,1.5,0,0" Padding="10">
            <DockPanel Height="170">
                <DockPanel DockPanel.Dock="Top" Margin="0,0,0,6">
                    <TextBlock Text="Registro de actividad" Foreground="{StaticResource TextoAcento}" FontWeight="Bold"/>
                    <Button x:Name="BtnLimpiarLog" Content="Limpiar" Width="80" HorizontalAlignment="Right" Margin="0"/>
                </DockPanel>
                <TextBox x:Name="LogBox" IsReadOnly="True" Background="#AA070A10" Foreground="#66AEFF" BorderBrush="{DynamicResource NeonBrush}"
                         FontFamily="Consolas" FontSize="12" TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto" AcceptsReturn="True"/>
            </DockPanel>
        </Border>

        <!-- Zona de contenido: barra de seccion + pestanas (sin franja) + panel lateral superpuesto -->
        <Grid x:Name="ZonaContenido" ClipToBounds="True">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Margin="10,10,10,0" Padding="8,6" CornerRadius="14" BorderThickness="1.5"
                BorderBrush="{DynamicResource NeonBrush}" Background="#33141C30">
            <DockPanel LastChildFill="True">
                <Button x:Name="BtnMenuLateral" DockPanel.Dock="Left" Content="☰  MENÚ" Width="120" Height="34" Margin="0,0,14,0"
                        Padding="0" HorizontalContentAlignment="Center" FontWeight="Bold"
                        Background="#33141C30" BorderBrush="{DynamicResource NeonBrush}" ToolTip="Abrir el menu de secciones"/>
                <TextBlock x:Name="TxtSeccionActual" Text="" Foreground="{StaticResource TextoPrimario}" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/>
            </DockPanel>
        </Border>

        <TabControl x:Name="TabControlPrincipal" Grid.Row="1" Style="{StaticResource TabSinCabecera}" Margin="10,8,10,10" Background="{StaticResource BgPrincipal}" BorderThickness="0">

            <TabItem Header="🏠 Inicio" IsSelected="True">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="14">
                        <TextBlock Text="Resumen del equipo" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="18" Margin="0,0,0,14"/>

                        <UniformGrid Columns="4" Rows="1" Margin="0,0,0,14">
                            <Border Style="{StaticResource TarjetaSeccion}" Margin="0,0,8,0">
                                <StackPanel>
                                    <TextBlock Text="🧮 CPU" Foreground="{StaticResource TextoSecundario}" FontSize="12"/>
                                    <TextBlock x:Name="TxtInicioCPU" Text="--%" Foreground="White" FontWeight="Bold" FontSize="22" Margin="0,4,0,0"/>
                                </StackPanel>
                            </Border>
                            <Border Style="{StaticResource TarjetaSeccion}" Margin="0,0,8,0">
                                <StackPanel>
                                    <TextBlock Text="🧠 RAM" Foreground="{StaticResource TextoSecundario}" FontSize="12"/>
                                    <TextBlock x:Name="TxtInicioRAM" Text="--%" Foreground="White" FontWeight="Bold" FontSize="22" Margin="0,4,0,0"/>
                                </StackPanel>
                            </Border>
                            <Border Style="{StaticResource TarjetaSeccion}" Margin="0,0,8,0">
                                <StackPanel>
                                    <TextBlock Text="💽 Disco (C:)" Foreground="{StaticResource TextoSecundario}" FontSize="12"/>
                                    <TextBlock x:Name="TxtInicioDisco" Text="--%" Foreground="White" FontWeight="Bold" FontSize="22" Margin="0,4,0,0"/>
                                </StackPanel>
                            </Border>
                            <Border Style="{StaticResource TarjetaSeccion}">
                                <StackPanel>
                                    <TextBlock Text="⏱️ Tiempo activo" Foreground="{StaticResource TextoSecundario}" FontSize="12"/>
                                    <TextBlock x:Name="TxtInicioUptime" Text="--" Foreground="White" FontWeight="Bold" FontSize="18" Margin="0,4,0,0"/>
                                </StackPanel>
                            </Border>
                        </UniformGrid>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="💻 Sistema" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" Margin="0,0,0,8"/>
                                <TextBlock x:Name="TxtInicioSistema" Text="Cargando informacion del sistema..." Foreground="White" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="⚡ Acciones rapidas" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>
                                <WrapPanel>
                                    <Button x:Name="BtnInicioLimpiarTemp" Content="🧹 Limpiar temporales" Width="220" Height="46" FontSize="12"/>
                                    <Button x:Name="BtnInicioLiberarRAM" Content="🧠 Liberar RAM (basica)" Width="220" Height="46" FontSize="12"/>
                                    <Button x:Name="BtnInicioPerfilBajo" Content="🔋 Aplicar perfil de bajo consumo" Width="260" Height="46" FontSize="12"/>
                                    <Button x:Name="BtnInicioDiagnostico" Content="🩺 Diagnostico completo" Width="220" Height="46" FontSize="12"/>
                                    <Button x:Name="BtnInicioActualizar" Content="🔄 Actualizar resumen" Width="220" Height="46" FontSize="12" BorderBrush="{StaticResource Acento}"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="⚙️ Optimizar Windows">
                <DockPanel Margin="10">
                    <TextBlock DockPanel.Dock="Top" Text="Selecciona una categoria:" Foreground="#66AEFF" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                    <ComboBox x:Name="CmbCategoriaOptimizar" DockPanel.Dock="Top" Margin="0,0,0,14" Width="320" HorizontalAlignment="Left">
                        <ComboBoxItem Content="Perfiles de Optimizacion" IsSelected="True"/>
                        <ComboBoxItem Content="Acelerar funcionamiento del procesador"/>
                        <ComboBoxItem Content="Liberar RAM"/>
                    </ComboBox>

                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <Grid>
                            <!-- Panel: Perfiles de Optimizacion -->
                            <WrapPanel x:Name="PanelPerfiles">
                                <Button x:Name="BtnPerfilBajo" Width="300" Height="90">
                                    <StackPanel>
                                        <TextBlock Text="🔋 Equipo de bajo consumo" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Ideal para PCs con poca RAM o disco lento. Desactiva servicios innecesarios para maxima velocidad." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="BtnPerfilModerno" Width="300" Height="90">
                                    <StackPanel>
                                        <TextBlock Text="🖥️ Equipo moderno" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Para equipos con buen hardware. Quita bloatware y telemetria manteniendo funciones utiles." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="BtnPerfilGamer" Width="300" Height="90">
                                    <StackPanel>
                                        <TextBlock Text="🎮 Equipo gamer" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Mejora el rendimiento en juegos: energia al maximo, modo juego, GPU y red optimizadas." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="BtnPerfilRestaurar" Width="300" Height="90" BorderBrush="#A85050">
                                    <StackPanel>
                                        <TextBlock Text="↩️ Restaurar configuracion predeterminada" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Revierte los cambios aplicados por cualquiera de los perfiles anteriores." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="BtnQuitarAppsWindows" Width="300" Height="90" BorderBrush="#2F7CF6">
                                    <StackPanel>
                                        <TextBlock Text="🗑️ Quitar apps de Windows" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Lista las apps de la tienda instaladas (Xbox, Noticias, Clima, Teams...) incluida Microsoft Store, y quita las que elijas." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="BtnModoManual" Width="300" Height="90" BorderBrush="#2F7CF6">
                                    <StackPanel>
                                        <TextBlock Text="🔧 Modo manual (elige tu los ajustes)" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Marca uno por uno los servicios y ajustes de CPU, RAM y disco que quieras aplicar." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                            </WrapPanel>

                            <!-- Panel: Acelerar procesador -->
                            <WrapPanel x:Name="PanelAcelerarCPU" Visibility="Collapsed">
                                <Button x:Name="BtnAcelerarCPU" Width="320" Height="100" BorderBrush="#2F7CF6">
                                    <StackPanel>
                                        <TextBlock Text="⚡ Acelerar funcionamiento del procesador" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Alto rendimiento, sin 'estacionamiento' de nucleos, frecuencia minima al 100% y prioridad para la app activa." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                            </WrapPanel>

                            <!-- Panel: Liberar RAM -->
                            <WrapPanel x:Name="PanelLiberarRAM" Visibility="Collapsed">
                                <Button x:Name="BtnRamBasica" Width="300" Height="90">
                                    <StackPanel>
                                        <TextBlock Text="🟢 Basica" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Vacia la memoria en uso de las apps abiertas sin cerrarlas. Rapido y seguro." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="BtnRamIntermedia" Width="300" Height="90">
                                    <StackPanel>
                                        <TextBlock Text="🟡 Intermedia" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Basica + limpieza de cache DNS y miniaturas." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="BtnRamExhaustiva" Width="300" Height="90" BorderBrush="#A85050">
                                    <StackPanel>
                                        <TextBlock Text="🔴 Exhaustiva" FontWeight="Bold" TextWrapping="Wrap"/>
                                        <TextBlock Text="Intermedia + purga la lista de memoria en espera del sistema. El modo mas agresivo." FontSize="11" TextWrapping="Wrap" Opacity="0.85"/>
                                    </StackPanel>
                                </Button>
                            </WrapPanel>
                        </Grid>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>

            <TabItem Header="🧩 Controladores">
                <DockPanel Margin="14">
                    <TextBlock DockPanel.Dock="Top" Text="Selecciona una opcion:" Foreground="#66AEFF" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                    <ComboBox x:Name="CmbSeccionControladores" DockPanel.Dock="Top" Margin="0,0,0,14" Width="360" HorizontalAlignment="Left">
                        <ComboBoxItem Content="Buscador de controladores" IsSelected="True"/>
                        <ComboBoxItem Content="Explorador de controladores instalados"/>
                    </ComboBox>

                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <Grid>
                            <!-- Panel: Buscador de controladores -->
                            <StackPanel x:Name="PanelBuscadorControladores" MaxWidth="640" HorizontalAlignment="Left">

                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="📋 Información del equipo" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <Button x:Name="BtnDetectarTodo" Content="🔎 Ver información del equipo" Height="40" FontWeight="Bold" HorizontalContentAlignment="Center"/>
                                        <TextBox x:Name="TxtDetalleCompleto" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True"
                                                 Background="#070A10" Foreground="#66AEFF" FontFamily="Consolas" FontSize="11"
                                                 Height="220" Margin="0,10,0,0" VerticalScrollBarVisibility="Auto"
                                                 Text="Pulsa 'Ver información del equipo' para ver todos los detalles: modelo, numero de serie, CPU, RAM, discos, placa madre, version de BIOS, GPU(s), red y Windows."/>
                                    </StackPanel>
                                </Border>

                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="🔽 ¿Qué quieres buscar?" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <UniformGrid Columns="3" Margin="0,0,0,14">
                                            <RadioButton x:Name="RbTipoGPU" Content="🎮 Tarjeta de video" GroupName="TipoBusqueda" Foreground="White" IsChecked="True"/>
                                            <RadioButton x:Name="RbTipoPlaca" Content="🖥️ Placa madre" GroupName="TipoBusqueda" Foreground="White"/>
                                            <RadioButton x:Name="RbTipoLaptop" Content="💻 Portatil / AIO" GroupName="TipoBusqueda" Foreground="White"/>
                                        </UniformGrid>

                                        <StackPanel x:Name="PanelGPU">
                                            <TextBlock Text="Fabricante:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,2"/>
                                            <ComboBox x:Name="CmbFabricanteGPU">
                                                <ComboBoxItem Content="NVIDIA"/>
                                                <ComboBoxItem Content="AMD"/>
                                                <ComboBoxItem Content="Intel"/>
                                            </ComboBox>
                                            <UniformGrid Columns="2" Margin="0,10,0,0">
                                                <Button x:Name="BtnBuscarGPU" Content="⬇️ Buscar controlador" Margin="0,0,4,0" BorderBrush="{StaticResource Acento}"/>
                                                <Button x:Name="BtnDetectarGPU" Content="🔎 Detectar (detalles)" Margin="4,0,0,0"/>
                                            </UniformGrid>
                                            <TextBlock x:Name="TxtGPUDetectada" Text="" Foreground="White" TextWrapping="Wrap" Margin="0,8,0,0" FontSize="12"/>
                                        </StackPanel>

                                        <StackPanel x:Name="PanelPlaca" Visibility="Collapsed">
                                            <TextBlock Text="Marca:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,2"/>
                                            <ComboBox x:Name="CmbMarcaPlaca">
                                                <ComboBoxItem Content="ASUS"/>
                                                <ComboBoxItem Content="MSI"/>
                                                <ComboBoxItem Content="Gigabyte"/>
                                                <ComboBoxItem Content="ASRock"/>
                                                <ComboBoxItem Content="Biostar"/>
                                                <ComboBoxItem Content="EVGA"/>
                                                <ComboBoxItem Content="Supermicro"/>
                                            </ComboBox>
                                            <UniformGrid Columns="2" Margin="0,10,0,0">
                                                <Button x:Name="BtnBuscarPlaca" Content="⬇️ Buscar controlador" Margin="0,0,4,0" BorderBrush="{StaticResource Acento}"/>
                                                <Button x:Name="BtnDetectarPlaca" Content="🔎 Detectar (detalles)" Margin="4,0,0,0"/>
                                            </UniformGrid>
                                            <TextBlock x:Name="TxtPlacaDetectada" Text="" Foreground="White" TextWrapping="Wrap" Margin="0,8,0,0" FontSize="12"/>
                                        </StackPanel>

                                        <StackPanel x:Name="PanelLaptop" Visibility="Collapsed">
                                            <TextBlock Text="Marca:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,2"/>
                                            <ComboBox x:Name="CmbFabricanteLaptop">
                                                <ComboBoxItem Content="HP"/><ComboBoxItem Content="Dell"/><ComboBoxItem Content="Lenovo"/>
                                                <ComboBoxItem Content="ASUS"/><ComboBoxItem Content="Acer"/><ComboBoxItem Content="MSI"/>
                                                <ComboBoxItem Content="Samsung"/><ComboBoxItem Content="Toshiba/Dynabook"/><ComboBoxItem Content="Huawei"/>
                                                <ComboBoxItem Content="Honor"/><ComboBoxItem Content="LG"/><ComboBoxItem Content="Microsoft Surface"/>
                                                <ComboBoxItem Content="Razer"/><ComboBoxItem Content="Fujitsu"/><ComboBoxItem Content="Gigabyte / AORUS"/>
                                                <ComboBoxItem Content="Panasonic"/><ComboBoxItem Content="VAIO"/><ComboBoxItem Content="Medion"/>
                                                <ComboBoxItem Content="Chuwi"/><ComboBoxItem Content="Xiaomi"/><ComboBoxItem Content="Positivo"/>
                                                <ComboBoxItem Content="Clevo/Sager"/><ComboBoxItem Content="Getac"/><ComboBoxItem Content="Framework"/>
                                                <ComboBoxItem Content="NEC"/>
                                            </ComboBox>
                                            <UniformGrid Columns="2" Margin="0,10,0,0">
                                                <Button x:Name="BtnBuscarLaptop" Content="⬇️ Buscar controlador" Margin="0,0,4,0" BorderBrush="{StaticResource Acento}"/>
                                                <Button x:Name="BtnDetectarLaptop" Content="🔎 Detectar (detalles)" Margin="4,0,0,0"/>
                                            </UniformGrid>
                                            <TextBlock x:Name="TxtLaptopDetectada" Text="" Foreground="White" TextWrapping="Wrap" Margin="0,8,0,0" FontSize="12"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>

                                <TextBlock Foreground="{StaticResource TextoSecundario}" FontSize="11" TextWrapping="Wrap" Margin="4,0,4,10"
                                           Text="Nota: cada búsqueda abre una ventana propia con el navegador. Si la página del fabricante no responde (ej. error 403), se redirige automáticamente a una búsqueda de respaldo."/>
                            </StackPanel>

                            <!-- Panel: Explorador de controladores instalados -->
                            <StackPanel x:Name="PanelExploradorControladores" Visibility="Collapsed" HorizontalAlignment="Left" MaxWidth="900">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="🧩 Explorador de controladores instalados" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,6"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,12"
                                                   Text="Elige una opcion: se abre una ventana con la lista lista para revisar (con boton Volver)."/>
                                        <WrapPanel>
                                        <Button x:Name="BtnExpVerTodos" Width="410" Height="70" Margin="0,0,12,10">
                                            <StackPanel>
                                                <TextBlock Text="📋 Ver controladores instalados" FontWeight="Bold" FontSize="14"/>
                                                <TextBlock Text="Lista completa: dispositivo, fabricante, version, fecha y estado." FontSize="11" Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            </StackPanel>
                                        </Button>
                                        <Button x:Name="BtnExpAtencion" Width="410" Height="70" Margin="0,0,12,10">
                                            <StackPanel>
                                                <TextBlock Text="🔍 Analizar controladores" FontWeight="Bold" FontSize="14"/>
                                                <TextBlock Text="Muestra solo los que estan antiguos o con problemas." FontSize="11" Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            </StackPanel>
                                        </Button>
                                        <Button x:Name="BtnExpFaltantes" Width="410" Height="70" Margin="0,0,12,10">
                                            <StackPanel>
                                                <TextBlock Text="🆕 Detectar controladores faltantes" FontWeight="Bold" FontSize="14"/>
                                                <TextBlock Text="Hardware sin controlador, con opcion de descargarlo e instalarlo." FontSize="11" Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            </StackPanel>
                                        </Button>
                                        <Button x:Name="BtnBuscarDriversObsoletos" Width="410" Height="70" Margin="0,0,12,10">
                                            <StackPanel>
                                                <TextBlock Text="🧹 Obsoletos o no compatibles" FontWeight="Bold" FontSize="14"/>
                                                <TextBlock Text="Elige cuales borrar (se guarda una copia antes)." FontSize="11" Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            </StackPanel>
                                        </Button>
                                        <Button x:Name="BtnRepararDriversExp" Width="410" Height="70" Margin="0,0,12,10">
                                            <StackPanel>
                                                <TextBlock Text="🩹 Reparar con problemas" FontWeight="Bold" FontSize="14"/>
                                                <TextBlock Text="Repara los controladores que tienen errores." FontSize="11" Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            </StackPanel>
                                        </Button>
                                        <Button x:Name="BtnBackupControladores" Width="410" Height="70" Margin="0,0,12,10">
                                            <StackPanel>
                                                <TextBlock Text="💾 Copia de seguridad" FontWeight="Bold" FontSize="14"/>
                                                <TextBlock Text="Guarda todos tus controladores en una carpeta." FontSize="11" Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            </StackPanel>
                                        </Button>
                                        <Button x:Name="BtnRestaurarControladoresBackup" Width="410" Height="70" Margin="0,0,12,10">
                                            <StackPanel>
                                                <TextBlock Text="♻️ Restaurar desde copia" FontWeight="Bold" FontSize="14"/>
                                                <TextBlock Text="Reinstala controladores desde una copia guardada." FontSize="11" Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                            </StackPanel>
                                        </Button>
                                        </WrapPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>

            <TabItem Header="📦 Programas">
                <DockPanel Margin="14">
                    <TextBlock DockPanel.Dock="Top" Text="Selecciona una opcion:" Foreground="#66AEFF" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                    <ComboBox x:Name="CmbSeccionProgramas" DockPanel.Dock="Top" Margin="0,0,0,14" Width="360" HorizontalAlignment="Left">
                        <ComboBoxItem Content="Instalar programas" IsSelected="True"/>
                        <ComboBoxItem Content="Desinstalar programas"/>
                        <ComboBoxItem Content="Archivos ISO"/>
                        <ComboBoxItem Content="Microsoft Store"/>
                    </ComboBox>

                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <Grid>
                            <!-- Panel: Instalar programas -->
                            <StackPanel x:Name="PanelInstalarProgramas" MaxWidth="640" HorizontalAlignment="Left">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="📥 Catalogo de programas" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10"
                                                   Text="Marca los programas que quieras instalar y pulsa 'Instalar seleccionados'. Se descargan e instalan automaticamente usando el Instalador de aplicaciones de Windows (winget), con una barra de progreso en tiempo real."/>
                                        <StackPanel x:Name="PanelChecklistProgramas"/>
                                        <Button x:Name="BtnInstalarSeleccionados" Content="⬇️ Instalar seleccionados" Height="42" Margin="0,14,0,0" BorderBrush="{StaticResource Acento}"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Desinstalar programas -->
                            <StackPanel x:Name="PanelDesinstalarProgramas" MaxWidth="640" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="🗑️ Desinstalar programas" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,14"
                                                   Text="Abre la lista de programas instalados. Desde ahi puedes desinstalar sin dejar rastros (archivos, AppData, accesos directos y registro) o forzar la desinstalacion de un programa que no se deja quitar."/>
                                        <Button x:Name="BtnVerProgramasInstalados" Content="📋 Ver programas instalados" Height="46" FontSize="14" FontWeight="Bold"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Archivos ISO -->
                            <StackPanel x:Name="PanelArchivosISO" MaxWidth="640" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="💿 Descargar Windows, Office o Linux (ISO)" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,14"
                                                   Text="Elige que quieres descargar. Windows/Office descargan directo de los servidores de Microsoft (algunas versiones abren el navegador integrado si Microsoft exige seleccion manual). Las distros de Linux son de descarga libre: varias se descargan directo, el resto abre la pagina oficial del proyecto."/>

                                        <TextBlock Text="¿Que quieres descargar?" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                        <ComboBox x:Name="CmbTipoISO" Margin="0,0,0,12">
                                            <ComboBoxItem Content="Windows" IsSelected="True"/>
                                            <ComboBoxItem Content="Office"/>
                                            <ComboBoxItem Content="Linux"/>
                                        </ComboBox>

                                        <TextBlock Text="Version / distro:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                        <ComboBox x:Name="CmbVersionISO" Margin="0,0,0,12"/>

                                        <TextBlock Text="Idioma:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                        <ComboBox x:Name="CmbIdiomaISO" Margin="0,0,0,6"/>
                                        <TextBlock Foreground="{StaticResource TextoSecundario}" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,14"
                                                   Text="Nota: la mayoria de ISOs de Windows y Linux incluyen varios idiomas en el mismo archivo; el idioma se termina de elegir durante la instalacion."/>

                                        <Button x:Name="BtnDescargarISO" Content="⬇️ Descargar" Height="42" BorderBrush="{StaticResource Acento}"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Microsoft Store -->
                            <StackPanel x:Name="PanelMicrosoftStore" MaxWidth="640" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="🛒 Microsoft Store" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,14"
                                                   Text="1. Pulsa 'Buscar en la pagina web' y encuentra la app que quieras (ej. Lenovo Vantage).&#10;2. Copia el enlace de su pagina (o el codigo de 12 caracteres que aparece al final del enlace).&#10;3. Pegalo aqui abajo y pulsa 'Descargar e instalar'. Se instala directo desde la Tienda, sin volver a abrir el navegador ni la app Tienda."/>

                                        <TextBlock Text="Buscar la app en la Tienda:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                        <DockPanel Margin="0,0,0,14">
                                            <Button x:Name="BtnBuscarStoreWeb" DockPanel.Dock="Right" Content="🌐 Buscar" Width="110" Margin="8,0,0,0"/>
                                            <TextBox x:Name="TxtBuscarStore" Padding="8,6"/>
                                        </DockPanel>

                                        <TextBlock Text="Enlace o ID de la app (apps.microsoft.com/detail/XXXXXXXXXXXX):" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4" TextWrapping="Wrap"/>
                                        <TextBox x:Name="TxtLinkStore" Padding="8,6" Margin="0,0,0,14"/>

                                        <Button x:Name="BtnDescargarLinkStore" Content="⬇️ Descargar e instalar" Height="42" BorderBrush="{StaticResource Acento}"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>

            <TabItem Header="💾 Disco y almacenamiento">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <WrapPanel Margin="10">
                    <Button x:Name="BtnTemp" Width="285" Height="58" FontSize="12" Content="🧹 Limpiar archivos temporales"/>
                    <Button x:Name="BtnPapelera" Width="285" Height="58" FontSize="12" Content="🗑️ Vaciar papelera de reciclaje"/>
                    <Button x:Name="BtnWU" Width="285" Height="58" FontSize="12" Content="📦 Limpiar cache de Windows Update"/>
                    <Button x:Name="BtnCleanmgr" Width="285" Height="58" FontSize="12" Content="🧰 Abrir Liberador de espacio en disco"/>
                    <Button x:Name="BtnOptimizarUnidades" Width="285" Height="58" FontSize="12" Content="⚙️ Optimizar unidades (TRIM/desfragmentar)"/>
                    <Button x:Name="BtnChkdsk" Width="285" Height="58" FontSize="12" Content="🩺 Programar comprobacion de disco (chkdsk)"/>
                    <Button x:Name="BtnStorageSense" Width="285" Height="58" FontSize="12" Content="🧽 Activar Storage Sense (limpieza automatica)"/>
                    <Button x:Name="BtnMiniaturas" Width="285" Height="58" FontSize="12" Content="🖼️ Limpiar cache de miniaturas"/>
                    <Button x:Name="BtnVolcados" Width="285" Height="58" FontSize="12" Content="💥 Limpiar volcados de memoria (crash dumps)"/>
                    <Button x:Name="BtnDISM" Width="285" Height="58" FontSize="12" Content="🧹 Limpieza profunda de componentes (DISM)"/>
                    <Button x:Name="BtnCarpetasPesadas" Width="285" Height="58" FontSize="12" Content="📁 Ver carpetas mas pesadas del usuario"/>
                    <Button x:Name="BtnWsReset" Width="285" Height="58" FontSize="12" Content="🔄 Restablecer cache de Microsoft Store"/>
                </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="🧠 Memoria y rendimiento">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <WrapPanel Margin="10">
                    <Button x:Name="BtnResumen" Width="285" Height="58" FontSize="12" Content="📊 Ver resumen del sistema"/>
                    <Button x:Name="BtnProcesos" Width="285" Height="58" FontSize="12" Content="📈 Ver/cerrar procesos que mas RAM consumen"/>
                    <Button x:Name="BtnMemVirtual" Width="285" Height="58" FontSize="12" Content="💽 Configurar memoria virtual"/>
                    <Button x:Name="BtnEfectos" Width="285" Height="58" FontSize="12" Content="🎛️ Ajustar efectos visuales"/>
                    <Button x:Name="BtnEnergia" Width="285" Height="58" FontSize="12" Content="🔌 Plan de energia de alto rendimiento"/>
                    <Button x:Name="BtnSysMainOn" Width="285" Height="58" FontSize="12" Content="▶️ Activar SysMain (Superfetch)"/>
                    <Button x:Name="BtnSysMainOff" Width="285" Height="58" FontSize="12" Content="⏸️ Desactivar SysMain (Superfetch)"/>
                    <Button x:Name="BtnRevisarInicio" Width="285" Height="58" FontSize="12" Content="🚀 Revisar programas de inicio"/>
                    <Button x:Name="BtnTaskMgr" Width="285" Height="58" FontSize="12" Content="📋 Abrir Administrador de tareas"/>
                    <Button x:Name="BtnResMon" Width="285" Height="58" FontSize="12" Content="📉 Abrir Monitor de recursos"/>
                    <Button x:Name="BtnServicios" Width="285" Height="58" FontSize="12" Content="🧩 Abrir Servicios de Windows"/>
                    <Button x:Name="BtnPriorizarCPU" Width="285" Height="58" FontSize="12" Content="⚡ Priorizar CPU para primer plano"/>
                    <Button x:Name="BtnBackgroundAppsOff" Width="285" Height="58" FontSize="12" Content="📵 Desactivar apps en segundo plano"/>
                </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="🔄 Windows Update">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <WrapPanel Margin="10">
                    <Button x:Name="BtnDevMgmt" Width="285" Height="58" FontSize="12" Content="🛠️ Abrir Administrador de dispositivos"/>
                    <Button x:Name="BtnUpdatesOpc" Width="285" Height="58" FontSize="12" Content="⬇️ Ver actualizaciones opcionales de drivers"/>
                    <Button x:Name="BtnDriversAuto" Width="285" Height="58" FontSize="12" Content="🤖 Actualizar controladores automaticamente"/>
                    <Button x:Name="BtnPausarUpdates" Width="285" Height="58" FontSize="12" Content="⏸️ Pausar actualizaciones 7 dias"/>
                    <Button x:Name="BtnDeshabilitarUpdates" Width="285" Height="58" FontSize="12" Content="⛔ Deshabilitar Windows Update"/>
                    <Button x:Name="BtnReanudarUpdates" Width="285" Height="58" FontSize="12" Content="▶️ Reanudar actualizaciones"/>
                    <Button x:Name="BtnForzarUpdate" Width="285" Height="58" FontSize="12" Content="🔄 Forzar busqueda de actualizaciones"/>
                    <Button x:Name="BtnHistorialUpdates" Width="285" Height="58" FontSize="12" Content="📜 Ver historial de actualizaciones"/>
                    <Button x:Name="BtnRepararWU" Width="285" Height="58" FontSize="12" Content="🛠️ Reparar Windows Update (reset completo)"/>
                    <Button x:Name="BtnDefenderUpdate" Width="285" Height="58" FontSize="12" Content="🛡️ Actualizar firmas de Windows Defender"/>
                </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="🌐 Red y seguridad">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <WrapPanel Margin="10">
                    <Button x:Name="BtnDNS" Width="285" Height="58" FontSize="12" Content="🌐 Vaciar cache DNS"/>
                    <Button x:Name="BtnRenovarIP" Width="285" Height="58" FontSize="12" Content="🔄 Renovar direccion IP"/>
                    <Button x:Name="BtnDefender" Width="285" Height="58" FontSize="12" Content="🛡️ Analisis rapido con Windows Defender"/>
                    <Button x:Name="BtnVerAdaptadores" Width="285" Height="58" FontSize="12" Content="📶 Ver adaptadores de red"/>
                    <Button x:Name="BtnReiniciarRed" Width="285" Height="58" FontSize="12" Content="🔁 Reiniciar adaptadores de red"/>
                    <Button x:Name="BtnResetWinsock" Width="285" Height="58" FontSize="12" Content="🧯 Restablecer Winsock y TCP/IP"/>
                    <Button x:Name="BtnVerIP" Width="285" Height="58" FontSize="12" Content="🌍 Ver mi IP publica y privada"/>
                    <Button x:Name="BtnDefenderFull" Width="285" Height="58" FontSize="12" Content="🛡️ Analisis completo con Windows Defender"/>
                    <Button x:Name="BtnFirewallEstado" Width="285" Height="58" FontSize="12" Content="🧱 Verificar estado del Firewall"/>
                </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="🖥️ Sistema">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <WrapPanel Margin="10">
                    <Button x:Name="BtnExplorer" Width="285" Height="58" FontSize="12" Content="🔁 Reiniciar Explorer.exe"/>
                    <Button x:Name="BtnPuntoRestauracion" Width="285" Height="58" FontSize="12" Content="💾 Crear punto de restauracion"/>
                    <Button x:Name="BtnAbrirRestaurar" Width="285" Height="58" FontSize="12" Content="↩️ Abrir Restaurar sistema"/>
                    <Button x:Name="BtnSFC" Width="285" Height="58" FontSize="12" Content="🔍 Verificar archivos de sistema (SFC)"/>
                    <Button x:Name="BtnDISMRestore" Width="285" Height="58" FontSize="12" Content="🩹 Reparar imagen de Windows (DISM)"/>
                    <Button x:Name="BtnVariablesEntorno" Width="285" Height="58" FontSize="12" Content="🌱 Variables de entorno"/>
                    <Button x:Name="BtnInformeEnergia" Width="285" Height="58" FontSize="12" Content="🔋 Generar informe de energia"/>
                    <Button x:Name="BtnReiniciarEquipo" Width="285" Height="58" FontSize="12" Content="🔃 Reiniciar equipo"/>
                    <Button x:Name="BtnApagarEquipo" Width="285" Height="58" FontSize="12" Content="⏻ Apagar equipo"/>

                    <TextBlock Width="620" Text="Windows 11" FontWeight="Bold" Foreground="{StaticResource TextoAcento}" FontSize="15" Margin="4,16,4,4"/>
                    <Button x:Name="BtnBajaLatenciaOn" Width="285" Height="58" FontSize="12" Content="⚡ Activar Perfil de Baja Latencia"/>
                    <Button x:Name="BtnBajaLatenciaOff" Width="285" Height="58" FontSize="12" Content="↩️ Desactivar Perfil de Baja Latencia"/>
                    <Button x:Name="BtnMenuClasico" Width="285" Height="58" FontSize="12" Content="🖱️ Menu contextual clasico (estilo Win10)"/>
                    <Button x:Name="BtnMenuModerno" Width="285" Height="58" FontSize="12" Content="🖱️ Menu contextual moderno (Win11)"/>
                    <Button x:Name="BtnTaskbarIzquierda" Width="285" Height="58" FontSize="12" Content="⬅️ Barra de tareas a la izquierda"/>
                    <Button x:Name="BtnTaskbarCentrada" Width="285" Height="58" FontSize="12" Content="🔳 Barra de tareas centrada (por defecto)"/>
                    <Button x:Name="BtnSegundosOn" Width="285" Height="58" FontSize="12" Content="🕐 Mostrar segundos en el reloj"/>
                    <Button x:Name="BtnSegundosOff" Width="285" Height="58" FontSize="12" Content="🕐 Ocultar segundos en el reloj"/>
                    <Button x:Name="BtnWidgetsOff" Width="285" Height="58" FontSize="12" Content="📰 Ocultar boton de Widgets"/>
                    <Button x:Name="BtnWidgetsOn" Width="285" Height="58" FontSize="12" Content="📰 Mostrar boton de Widgets"/>
                    <Button x:Name="BtnFinalizarTarea" Width="285" Height="58" FontSize="12" Content="❌ Activar 'Finalizar tarea' en la barra"/>
                    <Button x:Name="BtnSnapOff" Width="285" Height="58" FontSize="12" Content="🪟 Desactivar Snap Layouts"/>
                    <Button x:Name="BtnSnapOn" Width="285" Height="58" FontSize="12" Content="🪟 Activar Snap Layouts"/>
                    <Button x:Name="BtnConfigGraficos" Width="285" Height="58" FontSize="12" Content="🎮 Configuracion de graficos (Auto HDR)"/>
                    <Button x:Name="BtnEstadoActivacion" Width="285" Height="58" FontSize="12" Content="🔑 Ver estado de activacion de Windows"/>
                </WrapPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="🗂️ Registro de Windows">
                <DockPanel Margin="14">
                    <TextBlock DockPanel.Dock="Top" Text="Selecciona una opcion:" Foreground="#66AEFF" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                    <ComboBox x:Name="CmbSeccionRegistro" DockPanel.Dock="Top" Margin="0,0,0,14" Width="360" HorizontalAlignment="Left">
                        <ComboBoxItem Content="Edicion del registro" IsSelected="True"/>
                        <ComboBoxItem Content="Optimizacion"/>
                        <ComboBoxItem Content="Analisis y reparacion de errores"/>
                    </ComboBox>

                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <Grid>
                            <!-- Panel: Edicion del registro -->
                            <StackPanel x:Name="PanelEdicionRegistro" MaxWidth="640" HorizontalAlignment="Left">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="⚠️ Seguridad primero" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10"
                                                   Text="Editar el registro puede afectar el funcionamiento de Windows. Se recomienda crear un punto de restauracion antes de aplicar cambios."/>
                                        <UniformGrid Columns="2">
                                            <Button x:Name="BtnBackupRegistro" Content="💾 Crear punto de restauracion" Margin="0,0,4,0" BorderBrush="{StaticResource Acento}"/>
                                            <Button x:Name="BtnRestaurarRegistro" Content="↩️ Abrir Restaurar sistema" Margin="4,0,0,0"/>
                                        </UniformGrid>
                                        <Button x:Name="BtnAbrirRegedit" Content="🛠️ Abrir el Editor del Registro (regedit)" Margin="0,10,0,0"/>
                                    </StackPanel>
                                </Border>

                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="✏️ Ediciones rapidas del registro" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10"
                                                   Text="Marca uno o varios ajustes y pulsa 'Aplicar seleccionados'."/>
                                        <StackPanel x:Name="PanelChecklistRegistro"/>
                                        <Button x:Name="BtnAplicarRegistro" Content="✅ Aplicar seleccionados" Height="42" Margin="0,10,0,0" BorderBrush="{StaticResource Acento}"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Optimizacion del registro -->
                            <StackPanel x:Name="PanelOptimizacionRegistro" MaxWidth="640" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="⚡ Optimizacion de rendimiento" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10"
                                                   Text="Claves del registro enfocadas especificamente en rendimiento (disco, memoria, respuesta del sistema y red). Marca uno o varios ajustes y pulsa 'Aplicar seleccionados'. Algunos requieren reiniciar para notarse."/>
                                        <StackPanel x:Name="PanelChecklistOptimizacionRegistro"/>
                                        <Button x:Name="BtnAplicarOptimizacionRegistro" Content="✅ Aplicar seleccionados" Height="42" Margin="0,10,0,0" BorderBrush="{StaticResource Acento}"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Analisis y reparacion de errores -->
                            <StackPanel x:Name="PanelAnalisisRegistro" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="🔍 Analisis del registro" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10"
                                                   Text="Busca programas de inicio rotos, entradas de desinstalacion huerfanas, DLL compartidas faltantes y rutas de servicios invalidas."/>
                                        <UniformGrid Columns="2">
                                            <Button x:Name="BtnAnalizarRegistro" Content="🔍 Analizar registro en busca de errores" Margin="0,0,4,0" BorderBrush="{StaticResource Acento}"/>
                                            <Button x:Name="BtnCorregirRegistro" Content="🩹 Corregir errores encontrados" Margin="4,0,0,0" BorderBrush="#A85050" Visibility="Collapsed"/>
                                        </UniformGrid>
                                        <TextBlock x:Name="TxtResumenRegistro" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,10,0,0"/>
                                    </StackPanel>
                                </Border>
                                <DataGrid x:Name="GridErroresRegistro" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single">
                                    <DataGrid.Columns>
                                        <DataGridTextColumn Header="Categoria" Binding="{Binding Categoria}" Width="1.6*"/>
                                        <DataGridTextColumn Header="Descripcion" Binding="{Binding Descripcion}" Width="2.2*"/>
                                        <DataGridTextColumn Header="Detalle" Binding="{Binding Detalle}" Width="2*"/>
                                    </DataGrid.Columns>
                                </DataGrid>
                            </StackPanel>
                        </Grid>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>

            <TabItem Header="🎨 Personalizacion">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="14" MaxWidth="640" HorizontalAlignment="Left">
                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="🖼️ Fondo de pantalla" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                <Button x:Name="BtnCambiarFondo" Content="Elegir imagen y aplicar como fondo de pantalla" Height="42"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="🌗 Tema" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                <UniformGrid Columns="2">
                                    <Button x:Name="BtnTemaOscuro" Content="🌙 Activar tema oscuro" Height="42" Margin="0,0,4,0"/>
                                    <Button x:Name="BtnTemaClaro" Content="☀️ Activar tema claro" Height="42" Margin="4,0,0,0"/>
                                </UniformGrid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="⚙️ Mas ajustes de personalizacion" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                <Button x:Name="BtnAbrirPersonalizacion" Content="🎨 Colores, temas y fondo (Configuracion de Windows)" Height="42" Margin="0,0,0,8"/>
                                <Button x:Name="BtnAbrirPantallaBloqueoConfig" Content="🔒 Pantalla de bloqueo" Height="42" Margin="0,0,0,8"/>
                                <Button x:Name="BtnAbrirSonidos" Content="🔊 Sonidos del sistema" Height="42" Margin="0,0,0,8"/>
                                <Button x:Name="BtnAbrirCursor" Content="🖱️ Puntero del mouse" Height="42"/>
                            </StackPanel>
                        </Border>

                        <TextBlock Foreground="{StaticResource TextoSecundario}" FontSize="11" TextWrapping="Wrap" Margin="4,4,4,0"
                                   Text="Nota: la transparencia, animaciones, protector de pantalla y demas efectos visuales estan en Registro de Windows → Edicion del registro."/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="💀 BSOD">
                <DockPanel Margin="10">
                    <TextBlock DockPanel.Dock="Top" Foreground="White" TextWrapping="Wrap" Margin="0,0,0,8"
                               Text="Pantallas azules registradas en el visor de sucesos de Windows, con el codigo de error y una recomendacion de que suele causarlo y como corregirlo."/>
                    <WrapPanel DockPanel.Dock="Top" Margin="0,0,0,10">
                        <Button x:Name="BtnActualizarBSODTab" Content="🔄 Actualizar historial" Width="210" Height="46" FontSize="12"/>
                        <Button x:Name="BtnExportarBSOD" Content="📤 Exportar historial" Width="210" Height="46" FontSize="12"/>
                        <Button x:Name="BtnConfigVolcado" Content="⚙️ Ver/activar volcados de memoria" Width="250" Height="46" FontSize="12"/>
                        <Button x:Name="BtnMonitorConfiabilidad" Content="📈 Monitor de confiabilidad" Width="230" Height="46" FontSize="12"/>
                        <Button x:Name="BtnDiagMemoriaTab" Content="🧠 Diagnostico de memoria" Width="230" Height="46" FontSize="12"/>
                        <Button x:Name="BtnAbrirMinidumpTab" Content="📁 Abrir carpeta de volcados" Width="230" Height="46" FontSize="12"/>
                        <Button x:Name="BtnDriversRecientes" Content="🕒 Controladores recientes" Width="230" Height="46" FontSize="12"/>
                        <Button x:Name="BtnSFCTab" Content="🔍 Verificar archivos de sistema" Width="230" Height="46" FontSize="12"/>
                    </WrapPanel>
                    <TextBlock x:Name="TxtResumenBSODTab" DockPanel.Dock="Top" Foreground="#66AEFF" FontWeight="Bold" Margin="0,0,0,8" TextWrapping="Wrap"/>
                    <DataGrid x:Name="GridBSODTab" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Fecha" Binding="{Binding Fecha}" Width="1.2*"/>
                            <DataGridTextColumn Header="Codigo" Binding="{Binding Codigo}" Width="*"/>
                            <DataGridTextColumn Header="Nombre del error" Binding="{Binding Nombre}" Width="1.6*"/>
                            <DataGridTextColumn Header="Recomendacion" Binding="{Binding Recomendacion}" Width="3.2*"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </DockPanel>
            </TabItem>

            <TabItem Header="🩺 Diagnosticar equipo">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <DockPanel Margin="10">
                    <TextBlock DockPanel.Dock="Top" Foreground="White" TextWrapping="Wrap" Margin="0,0,0,8"
                               Text="Prueba cada componente del equipo. Algunas pruebas requieren tu participacion (escuchar, ver, escribir); otras son automaticas."/>
                    <WrapPanel DockPanel.Dock="Top" Margin="0,0,0,8">
                        <Button x:Name="BtnProbarCamara" Content="📷 Probar camara (vista previa propia)" Width="230" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarTeclado" Content="⌨️ Probar teclado (virtual)" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarMicrofono" Content="🎙️ Probar microfono (nivel en vivo)" Width="220" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarAudioIzq" Content="🔊 Altavoz izquierdo" Width="170" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarAudioDer" Content="🔊 Altavoz derecho" Width="170" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarAudioAmbos" Content="🔊 Ambos altavoces" Width="170" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarPantalla" Content="🖥️ Probar pantalla (colores)" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnDetallesPantalla" Content="🖥️ Ver detalles de pantalla" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarRAM" Content="🧠 Probar memoria RAM (elegir tipo)" Width="220" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarAlmacenamiento" Content="💽 Verificar almacenamiento" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnVelocidadDisco" Content="💽 Velocidad de disco (lectura/escritura)" Width="240" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarVentiladores" Content="🌀 Verificar ventiladores" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarGrafica" Content="🎮 Ver tarjeta grafica" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarMouse" Content="🖱️ Probar mouse/touchpad" Width="200" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarBateria" Content="🔋 Verificar bateria" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarRed" Content="🌐 Probar red / Internet" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarTemperatura" Content="🌡️ Temperatura del procesador" Width="220" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarArranque" Content="⏱️ Tiempo de arranque" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarBluetooth" Content="📶 Verificar Bluetooth" Width="190" Height="46" FontSize="12"/>
                        <Button x:Name="BtnProbarUSB" Content="🔌 Dispositivos USB conectados" Width="220" Height="46" FontSize="12"/>
                        <Button x:Name="BtnDiagCompleto" Content="🧩 Diagnostico completo automatico" Width="240" Height="46" FontSize="12" BorderBrush="{StaticResource Acento}"/>
                    </WrapPanel>
                    <TextBox x:Name="TxtDiagResultados" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="240"
                             Background="#070A10" Foreground="#66AEFF" FontFamily="Consolas" FontSize="12"
                             VerticalScrollBarVisibility="Auto"
                             Text="Los resultados de cada prueba apareceran aqui. Ejecuta una o varias pruebas para ver el diagnostico."/>
                </DockPanel>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="🐞 Registro de errores">
                <DockPanel Margin="14">
                    <Border DockPanel.Dock="Top" Style="{StaticResource TarjetaSeccion}">
                        <StackPanel>
                            <TextBlock Text="🐞 Registro de errores del programa" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                            <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10"
                                       Text="Aqui se registran automaticamente todos los errores y avisos que ocurren mientras usas el programa, con su origen: si fue una prueba de diagnostico, una descarga, la instalacion/desinstalacion de un programa, un ajuste del registro, o un error inesperado del programa en si."/>
                            <DockPanel Margin="0,0,0,10" MaxWidth="500" HorizontalAlignment="Left">
                                <TextBlock Text="🔍" VerticalAlignment="Center" Margin="0,0,8,0" FontSize="14"/>
                                <TextBox x:Name="TxtBuscarError" Padding="8,6"/>
                            </DockPanel>
                            <DockPanel Margin="0,0,0,10" MaxWidth="360" HorizontalAlignment="Left">
                                <TextBlock Text="Categoria:" Foreground="White" VerticalAlignment="Center" Margin="0,0,8,0"/>
                                <ComboBox x:Name="CmbFiltroCategoriaError">
                                    <ComboBoxItem Content="Todas" IsSelected="True"/>
                                    <ComboBoxItem Content="Prueba de diagnostico"/>
                                    <ComboBoxItem Content="Descarga de archivos"/>
                                    <ComboBoxItem Content="Instalar/Desinstalar programas"/>
                                    <ComboBoxItem Content="Registro de Windows"/>
                                    <ComboBoxItem Content="Controladores"/>
                                    <ComboBoxItem Content="Perfiles de optimizacion"/>
                                    <ComboBoxItem Content="Programa general"/>
                                </ComboBox>
                            </DockPanel>
                            <WrapPanel>
                                <Button x:Name="BtnActualizarErrores" Content="🔄 Actualizar" Width="150" Height="42" FontSize="12"/>
                                <Button x:Name="BtnCopiarErrores" Content="📋 Copiar todo" Width="150" Height="42" FontSize="12"/>
                                <Button x:Name="BtnExportarErrores" Content="💾 Exportar a archivo" Width="170" Height="42" FontSize="12"/>
                                <Button x:Name="BtnLimpiarErrores" Content="🗑️ Limpiar registro" Width="160" Height="42" FontSize="12" BorderBrush="#A85050"/>
                            </WrapPanel>
                            <TextBlock x:Name="TxtResumenErrores" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,10,0,0"/>
                        </StackPanel>
                    </Border>
                    <DataGrid x:Name="GridRegistroErrores" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Hora" Binding="{Binding Hora}" Width="0.6*"/>
                            <DataGridTextColumn Header="Tipo" Binding="{Binding Tipo}" Width="0.5*"/>
                            <DataGridTextColumn Header="Categoria" Binding="{Binding Categoria}" Width="1.4*"/>
                            <DataGridTextColumn Header="Origen (funcion)" Binding="{Binding Origen}" Width="1.4*"/>
                            <DataGridTextColumn Header="Mensaje" Binding="{Binding Mensaje}" Width="3*"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </DockPanel>
            </TabItem>

            <TabItem Header="🛠️ Modificacion">
                <DockPanel Margin="14">
                    <TextBlock DockPanel.Dock="Top" Text="Selecciona una opcion:" Foreground="#66AEFF" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                    <ComboBox x:Name="CmbSeccionModificacion" DockPanel.Dock="Top" Margin="0,0,0,14" Width="360" HorizontalAlignment="Left">
                        <ComboBoxItem Content="Camara" IsSelected="True"/>
                        <ComboBoxItem Content="Pantalla"/>
                        <ComboBoxItem Content="Teclado"/>
                        <ComboBoxItem Content="Parlante"/>
                        <ComboBoxItem Content="Almacenamiento"/>
                    </ComboBox>

                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <Grid>
                            <!-- Panel: Camara -->
                            <Grid x:Name="PanelModCamara">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" MinWidth="380"/>
                                    <ColumnDefinition Width="280"/>
                                </Grid.ColumnDefinitions>

                                <Border Grid.Column="0" Style="{StaticResource TarjetaSeccion}" Margin="0,0,12,14">
                                    <StackPanel>
                                        <TextBlock Text="📷 Camara en vivo" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10" FontSize="12"
                                                   Text="Visualiza tu camara sin abrir la app Camara de Windows. Puedes rotarla o voltearla si la imagen se ve al reves (util con algunas camaras externas o de portatiles con la tapa girada)."/>
                                        <DockPanel Margin="0,0,0,10">
                                            <Button x:Name="BtnModCamaraActualizarLista" DockPanel.Dock="Right" Content="🔄" Width="42" Margin="8,0,0,0" ToolTip="Actualizar lista de camaras"/>
                                            <ComboBox x:Name="CmbModCamaraDispositivo"/>
                                        </DockPanel>
                                        <Border BorderBrush="#232B3D" BorderThickness="1" Background="#0A0D14" Height="340" CornerRadius="6">
                                            <Grid>
                                                <Image x:Name="ImgModCamara" Stretch="Uniform"/>
                                                <TextBlock x:Name="TxtModCamaraSinSenal" Text="Camara detenida. Pulsa 'Iniciar camara'." Foreground="{StaticResource TextoSecundario}" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="260"/>
                                            </Grid>
                                        </Border>
                                        <WrapPanel Margin="0,12,0,0">
                                            <Button x:Name="BtnModCamaraIniciar" Content="▶️ Iniciar camara" Width="160" Height="42" FontSize="12" BorderBrush="{StaticResource Acento}"/>
                                            <Button x:Name="BtnModCamaraDetener" Content="⏹️ Detener camara" Width="160" Height="42" FontSize="12" BorderBrush="#A85050"/>
                                        </WrapPanel>
                                        <TextBlock Text="Rotar y voltear:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,14,0,6"/>
                                        <WrapPanel>
                                            <Button x:Name="BtnModCamaraRotarIzq" Content="↺ Rotar izquierda" Width="155" Height="40" FontSize="12"/>
                                            <Button x:Name="BtnModCamaraRotarDer" Content="↻ Rotar derecha" Width="150" Height="40" FontSize="12"/>
                                            <Button x:Name="BtnModCamaraVoltearH" Content="⇋ Voltear horizontal" Width="165" Height="40" FontSize="12"/>
                                            <Button x:Name="BtnModCamaraVoltearV" Content="⇕ Voltear vertical" Width="150" Height="40" FontSize="12"/>
                                            <Button x:Name="BtnModCamaraRestablecer" Content="↩️ Restablecer" Width="130" Height="40" FontSize="12"/>
                                        </WrapPanel>
                                    </StackPanel>
                                </Border>

                                <Border Grid.Column="1" Style="{StaticResource TarjetaSeccion}" Margin="0,0,0,14">
                                    <StackPanel>
                                        <TextBlock Text="🔎 Detalles de la camara" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock x:Name="TxtModCamaraDetalles" Foreground="White" TextWrapping="Wrap" FontSize="12" Text="Selecciona 'Iniciar camara' para ver aqui sus detalles (nombre, controlador, resolucion, orientacion actual)."/>
                                    </StackPanel>
                                </Border>
                            </Grid>

                            <!-- Panel: Pantalla -->
                            <StackPanel x:Name="PanelModPantalla" MaxWidth="640" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="🖥️ Pantalla" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10" FontSize="12"
                                                   Text="Detecta tu(s) pantalla(s) y su informacion (incluye el modelo del panel interno en laptops cuando Windows lo reporta), y permite cambiar la frecuencia de actualizacion entre las que tu monitor y tarjeta grafica ya soportan."/>
                                        <Button x:Name="BtnModPantallaDetectar" Content="🔍 Detectar pantalla" Height="40" Width="200" HorizontalAlignment="Left" BorderBrush="{StaticResource Acento}"/>

                                        <TextBlock Text="Pantalla:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,14,0,4"/>
                                        <ComboBox x:Name="CmbModPantallaDispositivo" Margin="0,0,0,10"/>
                                        <TextBlock x:Name="TxtModPantallaDetalles" Foreground="White" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,14" Text="Pulsa 'Detectar pantalla' para ver los detalles."/>

                                        <TextBlock x:Name="TxtModPantallaSin144" Foreground="Orange" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,10" Visibility="Collapsed"
                                                   Text="Tu pantalla no admite una frecuencia mayor a 60 Hz, asi que no hay una frecuencia mas alta que elegir."/>

                                        <StackPanel x:Name="PanelModPantallaFrecuencia" Visibility="Collapsed">
                                            <TextBlock Text="Frecuencia de actualizacion:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                            <DockPanel Margin="0,0,0,10">
                                                <Button x:Name="BtnModPantallaAplicarFrecuencia" DockPanel.Dock="Right" Content="Aplicar" Width="100" Margin="8,0,0,0"/>
                                                <ComboBox x:Name="CmbModPantallaFrecuencia"/>
                                            </DockPanel>
                                            <Button x:Name="BtnModPantallaQuitarFrecuencia" Content="↩️ Quitar frecuencia fija (volver a la maxima nativa)" Height="38" HorizontalAlignment="Left" Margin="0,0,0,14"/>

                                            <Separator Margin="0,6,0,14" Background="#232B3D"/>
                                            <CheckBox x:Name="ChkModPantallaFrecuenciaEnergia" Content="Usar una frecuencia fija distinta segun la fuente de energia (solo mientras el programa este abierto)" Foreground="White" Margin="0,0,0,10" TextElement.FontSize="12"/>
                                            <TextBlock Text="Con cargador conectado:" Foreground="{StaticResource TextoAcento}" Margin="0,0,0,4"/>
                                            <ComboBox x:Name="CmbModPantallaFrecuenciaCA" Margin="0,0,0,10"/>
                                            <TextBlock Text="Con bateria:" Foreground="{StaticResource TextoAcento}" Margin="0,0,0,4"/>
                                            <ComboBox x:Name="CmbModPantallaFrecuenciaBateria" Margin="0,0,0,10"/>
                                            <Button x:Name="BtnModPantallaGuardarEnergia" Content="💾 Guardar preferencia" Height="40" Width="220" HorizontalAlignment="Left"/>
                                            <TextBlock Foreground="{StaticResource TextoSecundario}" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,0"
                                                       Text="Nota: esta preferencia se aplica solo mientras The Dragon Tool esta abierto (detecta el cambio entre bateria y cargador y ajusta la frecuencia automaticamente). No queda guardada como un ajuste permanente de Windows."/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Teclado -->
                            <StackPanel x:Name="PanelModTeclado" MaxWidth="900" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="⌨️ Teclado" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Text="Tipo de teclado:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                        <ComboBox x:Name="CmbModTecladoTipo" Margin="0,0,0,10" Width="300" HorizontalAlignment="Left">
                                            <ComboBoxItem Content="USB" IsSelected="True"/>
                                            <ComboBoxItem Content="PC (cable/PS2)"/>
                                            <ComboBoxItem Content="Laptop (integrado)"/>
                                        </ComboBox>
                                        <DockPanel Margin="0,0,0,10">
                                            <Button x:Name="BtnModTecladoDetectar" DockPanel.Dock="Right" Content="🔍 Detectar" Width="110" Margin="8,0,0,0"/>
                                            <TextBlock x:Name="TxtModTecladoDetectado" Foreground="White" TextWrapping="Wrap" FontSize="12" VerticalAlignment="Center" Text="Pulsa 'Detectar' para ver los teclados conectados."/>
                                        </DockPanel>
                                        <TextBlock Foreground="{StaticResource TextoSecundario}" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,10"
                                                   Text="Nota: Windows aplica el remapeo por igual a todos los teclados conectados (no distingue USB, PS2 o el integrado del laptop); el selector de arriba es solo para que ubiques el tuyo en la lista detectada. Los cambios se activan al cerrar sesion o reiniciar el equipo."/>

                                        <Border BorderBrush="#232B3D" BorderThickness="1" Background="#0A0D14" CornerRadius="6" Padding="10" Margin="0,0,0,10">
                                            <StackPanel>
                                                <TextBlock Text="Haz clic aqui abajo y luego presiona la tecla fisica que quieras remapear o bloquear:" Foreground="{StaticResource TextoAcento}" Margin="0,0,0,8" TextWrapping="Wrap"/>
                                                <Border x:Name="BorderModTecladoVisual" Focusable="True" Background="Transparent" BorderThickness="0">
                                                    <StackPanel x:Name="PanelModTecladoVisual" HorizontalAlignment="Center"/>
                                                </Border>
                                            </StackPanel>
                                        </Border>

                                        <TextBlock x:Name="TxtModTecladoSeleccionada" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,10" Text="Tecla seleccionada: (ninguna)"/>

                                        <TextBlock Text="Remapear a:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                        <ComboBox x:Name="CmbModTecladoDestino" Margin="0,0,0,8"/>
                                        <CheckBox x:Name="ChkModTecladoBloquear" Content="Bloquear esta tecla (que no haga nada)" Foreground="White" Margin="0,0,0,10"/>
                                        <Button x:Name="BtnModTecladoAgregar" Content="➕ Agregar a la lista" Height="40" Width="180" HorizontalAlignment="Left" Margin="0,0,0,14"/>

                                        <TextBlock Text="Remapeos pendientes:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,6"/>
                                        <DataGrid x:Name="GridModTecladoMapeos" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single" Height="140" Margin="0,0,0,10">
                                            <DataGrid.Columns>
                                                <DataGridTextColumn Header="Tecla original" Binding="{Binding OrigenEtiqueta}" Width="*"/>
                                                <DataGridTextColumn Header="Se convierte en" Binding="{Binding DestinoEtiqueta}" Width="*"/>
                                            </DataGrid.Columns>
                                        </DataGrid>
                                        <WrapPanel>
                                            <Button x:Name="BtnModTecladoQuitarUno" Content="🗑️ Quitar seleccionado" Width="180" Height="40" FontSize="12"/>
                                            <Button x:Name="BtnModTecladoAplicar" Content="✅ Aplicar cambios" Width="170" Height="40" FontSize="12" BorderBrush="{StaticResource Acento}"/>
                                            <Button x:Name="BtnModTecladoQuitarTodos" Content="♻️ Quitar remapeos guardados" Width="230" Height="40" FontSize="12" BorderBrush="#A85050"/>
                                        </WrapPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Parlante -->
                            <StackPanel x:Name="PanelModParlante" MaxWidth="640" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="🔊 Parlante" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <Button x:Name="BtnModParlanteDetectar" Content="🔍 Detectar parlantes" Height="40" Width="200" HorizontalAlignment="Left" BorderBrush="{StaticResource Acento}"/>
                                        <TextBlock x:Name="TxtModParlanteDetalles" Foreground="White" TextWrapping="Wrap" FontSize="12" Margin="0,14,0,14" Text="Pulsa 'Detectar parlantes' para ver los dispositivos de audio y su informacion."/>

                                        <StackPanel x:Name="PanelModParlanteOpciones" Visibility="Collapsed">
                                            <TextBlock Text="Volumen:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                            <DockPanel Margin="0,0,0,10">
                                                <TextBlock x:Name="TxtModParlanteVolumenValor" DockPanel.Dock="Right" Text="--%" Foreground="White" Width="50" TextAlignment="Right" VerticalAlignment="Center"/>
                                                <Slider x:Name="SliderModParlanteVolumen" Minimum="0" Maximum="100" TickFrequency="1" VerticalAlignment="Center"/>
                                            </DockPanel>
                                            <CheckBox x:Name="ChkModParlanteSilenciar" Content="Silenciar" Foreground="White" Margin="0,0,0,14"/>

                                            <CheckBox x:Name="ChkModParlanteRefuerzo" Content="Subir el volumen nativo de Windows al maximo (100%)" Foreground="White" Margin="0,0,0,14"/>

                                            <Separator Margin="0,0,0,14" Background="#232B3D"/>
                                            <TextBlock Text="🚀 Amplificar mas alla del 100%" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,6"/>
                                            <TextBlock Foreground="White" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,10"
                                                       Text="Esto SI amplifica de verdad por encima del 100%, usando Equalizer APO (gratis, de codigo abierto, usado por millones de personas): agrega una ganancia extra antes de que el audio llegue a tus altavoces o audifonos. Se instala una sola vez (durante su instalador, marca tu dispositivo de salida) y pide reiniciar el equipo esa unica vez. Despues de eso, el control de abajo ajusta la amplificacion al instante, sin volver a reiniciar."/>
                                            <Button x:Name="BtnModParlanteInstalarAPO" Content="⬇️ Instalar Equalizer APO" Height="40" Width="230" HorizontalAlignment="Left" BorderBrush="{StaticResource Acento}" Margin="0,0,0,14"/>

                                            <TextBlock Text="Nivel de amplificacion:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,4"/>
                                            <DockPanel Margin="0,0,0,6">
                                                <TextBlock x:Name="TxtModParlanteAmplificacionValor" DockPanel.Dock="Right" Text="100%" Foreground="White" Width="60" TextAlignment="Right" VerticalAlignment="Center"/>
                                                <Slider x:Name="SliderModParlanteAmplificacion" Minimum="100" Maximum="400" Value="100" TickFrequency="25" IsSnapToTickEnabled="True" IsEnabled="False" VerticalAlignment="Center"/>
                                            </DockPanel>
                                            <TextBlock x:Name="TxtModParlanteEstadoAPO" Foreground="{StaticResource TextoSecundario}" FontSize="11" TextWrapping="Wrap" Text="Equalizer APO no detectado todavia. Instalalo primero con el boton de arriba."/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Panel: Almacenamiento -->
                            <StackPanel x:Name="PanelModAlmacenamiento" MaxWidth="760" HorizontalAlignment="Left" Visibility="Collapsed">
                                <Border Style="{StaticResource TarjetaSeccion}">
                                    <StackPanel>
                                        <TextBlock Text="Almacenamiento" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,10" FontSize="12"
                                                   Text="Detecta discos duros (HDD), SSD, pendrives USB y tarjetas microSD/SD conectadas. Selecciona uno para ver su informacion detallada, quitar la proteccion de solo lectura, analizar errores y corregirlos."/>
                                        <Button x:Name="BtnModAlmacenamientoDetectar" Content="Detectar almacenamiento" Height="40" Width="230" HorizontalAlignment="Left" BorderBrush="{StaticResource Acento}"/>

                                        <TextBlock Text="Dispositivo:" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,14,0,4"/>
                                        <ComboBox x:Name="CmbModAlmacenamientoDispositivo" Margin="0,0,0,10"/>

                                        <Border BorderBrush="#232B3D" BorderThickness="1" Background="#0A0D14" CornerRadius="6" Padding="12" Margin="0,0,0,14">
                                            <TextBlock x:Name="TxtModAlmacenamientoDetalles" Foreground="White" TextWrapping="Wrap" FontSize="12" Text="Pulsa 'Detectar almacenamiento' y luego selecciona un dispositivo de la lista para ver aqui su informacion detallada."/>
                                        </Border>

                                        <TextBlock Text="Proteccion contra escritura" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,6"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8"
                                                   Text="Si el dispositivo esta marcado como solo lectura (comun en pendrives y tarjetas SD/microSD protegidas), este boton la quita usando diskpart y el registro de Windows."/>
                                        <Button x:Name="BtnModAlmacenamientoQuitarSoloLectura" Content="Quitar solo lectura" Height="40" Width="230" HorizontalAlignment="Left" Margin="0,0,0,14"/>

                                        <Separator Margin="0,0,0,14" Background="#232B3D"/>
                                        <TextBlock Text="Analizar y corregir errores" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,6"/>
                                        <TextBlock Foreground="White" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8"
                                                   Text="Analizar revisa el sistema de archivos y la superficie del disco en busca de errores sin modificar nada. Corregir aplica la reparacion automatica de Windows (equivalente a chkdsk /f /r); si el disco esta en uso, la correccion se programa para el proximo reinicio."/>
                                        <WrapPanel Margin="0,0,0,14">
                                            <Button x:Name="BtnModAlmacenamientoAnalizar" Content="Analizar errores" Width="200" Height="40" FontSize="12" BorderBrush="{StaticResource Acento}"/>
                                            <Button x:Name="BtnModAlmacenamientoCorregir" Content="Corregir errores" Width="200" Height="40" FontSize="12" BorderBrush="#A85050"/>
                                        </WrapPanel>
                                        <Border BorderBrush="#232B3D" BorderThickness="1" Background="#0A0D14" CornerRadius="6" Padding="12" Margin="0,0,0,14">
                                            <TextBlock x:Name="TxtModAlmacenamientoResultadoErrores" Foreground="White" TextWrapping="Wrap" FontSize="12" Text="Todavia no se ha ejecutado ningun analisis."/>
                                        </Border>

                                        <Separator Margin="0,0,0,14" Background="#232B3D"/>
                                        <TextBlock Text="Firmware" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" Margin="0,0,0,6"/>
                                        <TextBlock x:Name="TxtModAlmacenamientoFirmware" Foreground="White" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8" Text="Selecciona un dispositivo para ver su version de firmware actual."/>
                                        <TextBlock Foreground="{StaticResource TextoSecundario}" TextWrapping="Wrap" FontSize="11" Margin="0,0,0,8"
                                                   Text="El firmware de un disco es especifico de su fabricante, modelo y controlador exacto: instalar el archivo equivocado puede dejar el dispositivo inutilizable. Por eso este boton lleva directo a la pagina oficial del fabricante detectado, donde su propia herramienta identifica el modelo exacto y aplica (si existe) la actualizacion que corrige errores de forma segura."/>
                                        <Button x:Name="BtnModAlmacenamientoBuscarFirmware" Content="Buscar actualizacion de firmware" Height="40" Width="260" HorizontalAlignment="Left"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>

            <TabItem Header="ℹ️ Acerca de">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="20" MaxWidth="700" HorizontalAlignment="Left">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,16">
                            <Image x:Name="ImgLogoAcerca" Width="64" Height="64" Margin="0,0,14,0"/>
                            <StackPanel VerticalAlignment="Center">
                                <TextBlock Text="The Dragon Tool" Foreground="White" FontSize="24" FontWeight="Bold"/>
                                <TextBlock x:Name="TxtVersionAcerca" Text="Version 2.0 · Edicion Neon  |  Optimizacion, diagnostico y mantenimiento de Windows" Foreground="{StaticResource TextoAcento}" FontSize="13"/>
                            </StackPanel>
                        </StackPanel>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="Creado por Adrian Barrientos" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                                <TextBlock Foreground="White" TextWrapping="Wrap"
                                           Text="Todo dentro de este programa funciona con herramientas y APIs oficiales de Windows (WMI, registro, WinGet, DISM, PnP, Windows Update). No se incluye ni se descarga nada de fuentes no verificadas ni contenido pirata."/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="✨ Novedades de esta version" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" Margin="0,0,0,8"/>
                                <TextBlock Foreground="White" TextWrapping="Wrap" LineHeight="22" Text="🎨 Nueva interfaz neon: borde de ventana animado con degradado azul con blanco que fluye, fondo translucido con luces suaves en movimiento y barra de titulo propia (minimizar, maximizar, cerrar).&#10;✨ Boton de la barra de titulo para apagar o encender los efectos animados (modo rendimiento).&#10;☰ Panel lateral de navegacion: oculto al abrir; pulsa MENU para elegir una pestaña y se esconde solo (Esc tambien lo cierra).&#10;🔘 Todos los botones, campos de texto, tablas y barras de desplazamiento con estilo neon redondeado y translucido.&#10;📊 Barras de progreso animadas, con brillo que las recorre, aura y porcentaje en vivo.&#10;⬅ Boton 'Volver' en todas las ventanas que se abren.&#10;🧩 Controladores: el explorador ahora abre ventanas con listas rapidas (todos, que necesitan atencion, faltantes) y se agrego la busqueda de controladores obsoletos o no compatibles para seleccionarlos y borrarlos con copia de seguridad.&#10;🗑️ Programas: 'Desinstalar programas' abre una ventana con la lista de programas instalados, con buscador y los botones 'Desinstalar sin dejar rastros' y 'Forzar desinstalacion'.&#10;🛠️ Pestaña Modificacion: camara (rotar/voltear), pantalla (frecuencia de actualizacion), teclado, parlante y almacenamiento.&#10;🩺 Diagnostico ampliado: camara, teclado, microfono, altavoces, pantalla, RAM, almacenamiento, ventiladores, GPU, mouse, bateria, red, temperatura, arranque, Bluetooth, USB y diagnostico completo automatico.&#10;🚀 Ejecucion desde GitHub con un solo comando en cualquier equipo (ver abajo).&#10;📷 Camara corregida: la vista previa ahora se muestra en la pestaña Camara y en Diagnostico (descarga el componente la primera vez; requiere permiso de camara en Windows).&#10;🗑️ Quitar apps de Windows (Perfiles de optimizacion): lista las apps incluidas, incluida Microsoft Store, y las desinstala.&#10;🎞️ Mas animaciones: entrada escalonada de paneles, transicion entre pestañas, botones con zoom y efecto de respiracion."/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="📋 Que hace cada pestaña" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" Margin="0,0,0,8"/>
                                <TextBlock Foreground="White" TextWrapping="Wrap" LineHeight="22" Text="🏠 Inicio: resumen en vivo del equipo y accesos rapidos.&#10;⚙️ Optimizar Windows: perfiles, acelerar CPU, liberar RAM.&#10;🧩 Controladores: buscar e instalar controladores, explorador de instalados, faltantes y obsoletos, respaldo y limpieza.&#10;📦 Programas: instalar apps, desinstalar sin dejar rastros o forzado, ISOs de Windows/Office/Linux, Microsoft Store.&#10;🗂️ Registro de Windows: edicion, optimizacion y reparacion de errores del registro.&#10;💾 Disco y almacenamiento: limpieza de archivos y espacio en disco.&#10;🧠 Memoria y rendimiento: herramientas de RAM y procesos.&#10;🔄 Windows Update: control de actualizaciones.&#10;🌐 Red y seguridad: diagnostico de red y Windows Defender.&#10;🖥️ Sistema: reparacion de Windows, ajustes de Windows 11, activacion.&#10;🎨 Personalizacion: fondo de pantalla, temas.&#10;💀 BSOD: historial y analisis de pantallas azules.&#10;🩺 Diagnosticar equipo: pruebas de hardware independientes.&#10;🛠️ Modificacion: ajustes de camara, pantalla, teclado, parlante y almacenamiento.&#10;🐞 Registro de errores: bitacora de todo lo que falla en el programa."/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="🚀 Abrir desde cualquier equipo" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                                <TextBlock Foreground="White" TextWrapping="Wrap" Margin="0,0,0,6"
                                           Text="Abre PowerShell y ejecuta este comando; descarga siempre la ultima version y la abre como administrador:"/>
                                <TextBox IsReadOnly="True" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" Foreground="#66AEFF"
                                         Text="irm https://raw.githubusercontent.com/adrianalexander1611/TheDragonTool/main/iniciar.ps1 | iex"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource TarjetaSeccion}">
                            <StackPanel>
                                <TextBlock Text="⚠️ Aviso" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                                <TextBlock Foreground="White" TextWrapping="Wrap"
                                           Text="Algunas acciones modifican configuraciones importantes del sistema. Se recomienda crear un punto de restauracion antes de aplicar cambios grandes (Registro de Windows → Edicion del registro → Crear punto de restauracion)."/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

        </TabControl>

        <!-- Velo semitransparente: al pulsarlo se oculta el panel -->
        <Border x:Name="VeloNav" Grid.RowSpan="2" Background="#99000000" Cursor="Hand" Visibility="Collapsed" Opacity="0"/>

        <!-- Panel lateral izquierdo (se desliza y se auto-oculta al elegir una opcion) -->
        <Border x:Name="PanelLateral" Grid.RowSpan="2" HorizontalAlignment="Left" Width="300" Margin="0,8,0,8" Visibility="Collapsed"
                Background="#D9101420" BorderBrush="{DynamicResource NeonBrush}" BorderThickness="0,2,2,2" CornerRadius="0,22,22,0">
            <Border.RenderTransform>
                <TranslateTransform x:Name="DesplazaPanel" X="-340"/>
            </Border.RenderTransform>
            <DockPanel Margin="12,14,12,14">
                <DockPanel DockPanel.Dock="Top" Margin="8,0,4,10">
                    <Button x:Name="BtnCerrarNav" DockPanel.Dock="Right" Content="✕" Width="32" Height="32" Padding="0" Margin="0"
                            HorizontalContentAlignment="Center" ToolTip="Ocultar el menu"/>
                    <TextBlock Text="NAVEGACIÓN" Foreground="{StaticResource TextoAcento}" FontWeight="Bold" FontSize="14" VerticalAlignment="Center"/>
                </DockPanel>
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel x:Name="ContenedorNav" Margin="8,4,8,6"/>
                </ScrollViewer>
            </DockPanel>
        </Border>
        </Grid>
    </DockPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
# Marco neon animado y translucido alrededor de toda la ventana (barra de titulo propia)
Aplicar-MarcoNeon -Ventana $window -Principal

$Script:LogBox = $window.FindName("LogBox")

# Logo
try {
    $logoPath = Join-Path $Script:ScriptDir "logo.png"
    if (Test-Path $logoPath) {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = New-Object System.Uri($logoPath, [System.UriKind]::Absolute)
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $img = $window.FindName("ImgLogo")
        $img.Source = $bmp
        $imgAcerca = $window.FindName("ImgLogoAcerca")
        if ($imgAcerca) { $imgAcerca.Source = $bmp }
    }
} catch {}

# Estado de administrador
$txtAdmin = $window.FindName("TxtEstadoAdmin")
$btnAbrirAdmin = $window.FindName("BtnAbrirComoAdmin")
if (Test-Admin) {
    $txtAdmin.Text = "Ejecutando como Administrador ✔"
    $txtAdmin.Foreground = [System.Windows.Media.Brushes]::LightGreen
    if ($btnAbrirAdmin) { $btnAbrirAdmin.Visibility = 'Collapsed' }
} else {
    $txtAdmin.Text = "Sin permisos de administrador - algunas opciones estaran deshabilitadas."
    $txtAdmin.Foreground = [System.Windows.Media.Brushes]::Orange
    if ($btnAbrirAdmin) { $btnAbrirAdmin.Visibility = 'Visible' }
}
if ($btnAbrirAdmin) { $btnAbrirAdmin.Add_Click({ Accion-AbrirComoAdministrador }) }

# --- Enlace de botones a acciones ---
$window.FindName("BtnLimpiarLog").Add_Click({ $Script:LogBox.Clear() })

$window.FindName("BtnPerfilBajo").Add_Click({ Perfil-BajoConsumo })
$window.FindName("BtnPerfilModerno").Add_Click({ Perfil-EquipoModerno })
$window.FindName("BtnPerfilGamer").Add_Click({ Perfil-Gamer })
$window.FindName("BtnPerfilRestaurar").Add_Click({ Perfil-Restaurar })
$window.FindName("BtnModoManual").Add_Click({ Show-VentanaManual })
$window.FindName("BtnQuitarAppsWindows").Add_Click({ Show-VentanaAppsWindows })

# --- Pestaña Registro de Windows ---
function Mostrar-SeccionRegistro {
    param([string]$Seccion)
    $window.FindName("PanelEdicionRegistro").Visibility = if ($Seccion -eq 'Edicion') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelOptimizacionRegistro").Visibility = if ($Seccion -eq 'Optimizacion') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelAnalisisRegistro").Visibility = if ($Seccion -eq 'Analisis') { 'Visible' } else { 'Collapsed' }
}
$window.FindName("CmbSeccionRegistro").Add_SelectionChanged({
    $sel = $window.FindName("CmbSeccionRegistro").SelectedItem
    if (-not $sel) { return }
    switch ($sel.Content) {
        'Edicion del registro' { Mostrar-SeccionRegistro -Seccion 'Edicion' }
        'Optimizacion' { Mostrar-SeccionRegistro -Seccion 'Optimizacion' }
        'Analisis y reparacion de errores' { Mostrar-SeccionRegistro -Seccion 'Analisis' }
    }
})

$window.FindName("BtnBackupRegistro").Add_Click({ Accion-CrearPuntoRestauracion })
$window.FindName("BtnRestaurarRegistro").Add_Click({ Accion-AbrirRestaurarSistema })
$window.FindName("BtnAbrirRegedit").Add_Click({ Accion-AbrirRegedit })

# Construir dinamicamente el checklist de optimizacion del registro
$panelChecklistOptReg = $window.FindName("PanelChecklistOptimizacionRegistro")
$Script:_checkboxesOptimizacionRegistro = New-Object System.Collections.Generic.List[object]
$categoriasOptReg = $Script:ChecklistOptimizacionRegistro | ForEach-Object { $_.Categoria } | Select-Object -Unique
foreach ($cat in $categoriasOptReg) {
    $gb = New-Object System.Windows.Controls.GroupBox
    $gb.Header = $cat
    $gb.Foreground = [System.Windows.Media.Brushes]::White
    $gb.Margin = "0,0,0,10"
    $sp = New-Object System.Windows.Controls.StackPanel
    foreach ($item in ($Script:ChecklistOptimizacionRegistro | Where-Object { $_.Categoria -eq $cat })) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $item.Nombre
        $cb.Foreground = [System.Windows.Media.Brushes]::White
        $cb.Margin = "4"
        $cb.Tag = $item
        $sp.Children.Add($cb) | Out-Null
        $Script:_checkboxesOptimizacionRegistro.Add($cb) | Out-Null
    }
    $gb.Content = $sp
    $panelChecklistOptReg.Children.Add($gb) | Out-Null
}
$window.FindName("BtnAplicarOptimizacionRegistro").Add_Click({
    if (-not (Requiere-Admin)) { return }
    $seleccionados = @($Script:_checkboxesOptimizacionRegistro | Where-Object { $_.IsChecked -eq $true })
    if ($seleccionados.Count -eq 0) { Show-Aviso "No has seleccionado ningun ajuste." "Nada seleccionado"; return }
    if (-not (Show-Confirm "Se aplicaran $($seleccionados.Count) ajuste(s) de optimizacion seleccionados. Algunos requieren reiniciar para notarse. ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Aplicando optimizaciones de registro"
    $i = 0
    foreach ($cb in $seleccionados) {
        $i++
        $pct = [math]::Round(($i / $seleccionados.Count) * 100)
        $item = $cb.Tag
        Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Aplicando: $($item.Nombre)" -LogLinea "Aplicando: $($item.Nombre)"
        try { & $item.ValorOn } catch { Write-Log "No se pudo aplicar: $($item.Nombre)" -Tipo AVISO }
    }
    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Optimizaciones aplicadas."
    Write-Log "Optimizaciones de registro aplicadas: $($seleccionados.Count)." -Tipo OK
    Show-Aviso "Optimizaciones aplicadas. Reinicia el equipo para que las que lo requieren surtan efecto completo." "Listo"
})

# Construir dinamicamente el checklist de ediciones de registro
$panelChecklistReg = $window.FindName("PanelChecklistRegistro")
$Script:_checkboxesRegistro = New-Object System.Collections.Generic.List[object]
$categoriasReg = $Script:ChecklistRegistro | ForEach-Object { $_.Categoria } | Select-Object -Unique
foreach ($cat in $categoriasReg) {
    $gb = New-Object System.Windows.Controls.GroupBox
    $gb.Header = $cat
    $gb.Foreground = [System.Windows.Media.Brushes]::White
    $gb.Margin = "0,0,0,10"
    $sp = New-Object System.Windows.Controls.StackPanel
    foreach ($item in ($Script:ChecklistRegistro | Where-Object { $_.Categoria -eq $cat })) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $item.Nombre
        $cb.Foreground = [System.Windows.Media.Brushes]::White
        $cb.Margin = "4"
        $cb.Tag = $item
        $sp.Children.Add($cb) | Out-Null
        $Script:_checkboxesRegistro.Add($cb) | Out-Null
    }
    $gb.Content = $sp
    $panelChecklistReg.Children.Add($gb) | Out-Null
}

$window.FindName("BtnAplicarRegistro").Add_Click({
    if (-not (Requiere-Admin)) { return }
    $seleccionados = @($Script:_checkboxesRegistro | Where-Object { $_.IsChecked -eq $true })
    if ($seleccionados.Count -eq 0) { Show-Aviso "No has seleccionado ningun ajuste." "Nada seleccionado"; return }
    if (-not (Show-Confirm "Se aplicaran $($seleccionados.Count) ajuste(s) de registro seleccionados. Se recomienda tener una copia de seguridad reciente. ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Aplicando ajustes de registro"
    $i = 0
    foreach ($cb in $seleccionados) {
        $i++
        $pct = [math]::Round(($i / $seleccionados.Count) * 100)
        $item = $cb.Tag
        Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Aplicando: $($item.Nombre)" -LogLinea "Aplicando: $($item.Nombre)"
        try { & $item.ValorOn } catch { Write-Log "No se pudo aplicar: $($item.Nombre)" -Tipo AVISO }
    }
    Close-VentanaProgreso -Ventana $prog -MensajeFinal "Ajustes de registro aplicados."
    Write-Log "Ajustes de registro aplicados: $($seleccionados.Count)." -Tipo OK
    Show-Aviso "Ajustes de registro aplicados." "Listo"
})

# Analisis y reparacion de errores
$Script:_erroresRegistroActuales = @()
function Analizar-RegistroCompleto {
    $window.FindName("TxtResumenRegistro").Text = "Analizando el registro... esto puede tardar unos segundos."
    Wait-UI -Milisegundos 1
    Write-Log "Analizando el registro en busca de errores..."
    $errores = Get-ErroresRegistroCompleto
    $Script:_erroresRegistroActuales = $errores
    $window.FindName("GridErroresRegistro").ItemsSource = $errores
    $btnCorregir = $window.FindName("BtnCorregirRegistro")
    if ($errores.Count -eq 0) {
        $window.FindName("TxtResumenRegistro").Text = "No se encontraron errores en el registro."
        $btnCorregir.Visibility = 'Collapsed'
    } else {
        $window.FindName("TxtResumenRegistro").Text = "Se encontraron $($errores.Count) error(es) en el registro."
        $btnCorregir.Visibility = 'Visible'
    }
    Write-Log "Analisis de registro completado: $($errores.Count) error(es) encontrados." -Tipo OK
}
$window.FindName("BtnAnalizarRegistro").Add_Click({ Analizar-RegistroCompleto })
$window.FindName("BtnCorregirRegistro").Add_Click({
    if (-not (Requiere-Admin)) { return }
    if ($Script:_erroresRegistroActuales.Count -eq 0) { return }
    if (-not (Show-Confirm "Se corregiran $($Script:_erroresRegistroActuales.Count) error(es) detectados en el registro (se eliminaran las referencias rotas). Se recomienda tener una copia de seguridad. ¿Continuar?")) { return }

    $prog = New-VentanaProgreso -Titulo "Corrigiendo errores del registro"
    $i = 0
    $corregidos = 0
    foreach ($e in $Script:_erroresRegistroActuales) {
        $i++
        $pct = [math]::Round(($i / $Script:_erroresRegistroActuales.Count) * 100)
        Update-VentanaProgreso -Ventana $prog -Porcentaje $pct -Estado "Corrigiendo: $($e.Descripcion)" -LogLinea $e.Descripcion
        try {
            switch ($e.Categoria) {
                'Programa de inicio roto' { Remove-ItemProperty -Path $e.Ruta -Name $e.Valor -ErrorAction Stop; $corregidos++ }
                'DLL compartida huerfana' { Remove-ItemProperty -Path $e.Ruta -Name $e.Valor -ErrorAction Stop; $corregidos++ }
                'Entrada de desinstalacion huerfana' { Remove-Item -Path $e.Ruta -Recurse -Force -ErrorAction Stop; $corregidos++ }
                default {}
            }
        } catch {}
    }
    Close-VentanaProgreso -Ventana $prog -MensajeFinal "$corregidos error(es) corregido(s)."
    Write-Log "$corregidos error(es) del registro corregidos." -Tipo OK
    Analizar-RegistroCompleto
})

# --- Pestaña Programas: instalar (catalogo) y desinstalar (con limpieza) ---
function Mostrar-SeccionProgramas {
    param([string]$Seccion)
    $window.FindName("PanelInstalarProgramas").Visibility = if ($Seccion -eq 'Instalar') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelDesinstalarProgramas").Visibility = if ($Seccion -eq 'Desinstalar') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelArchivosISO").Visibility = if ($Seccion -eq 'ISO') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelMicrosoftStore").Visibility = if ($Seccion -eq 'Store') { 'Visible' } else { 'Collapsed' }
}
$window.FindName("CmbSeccionProgramas").Add_SelectionChanged({
    $sel = $window.FindName("CmbSeccionProgramas").SelectedItem
    if (-not $sel) { return }
    switch ($sel.Content) {
        'Instalar programas' { Mostrar-SeccionProgramas -Seccion 'Instalar' }
        'Desinstalar programas' { Mostrar-SeccionProgramas -Seccion 'Desinstalar' }
        'Archivos ISO' { Mostrar-SeccionProgramas -Seccion 'ISO' }
        'Microsoft Store' { Mostrar-SeccionProgramas -Seccion 'Store' }
    }
})

# --- Pestaña Modificacion: wiring de botones (Camara) ---
$window.FindName("BtnModCamaraIniciar").Add_Click({ Iniciar-CamaraModificacion })
$window.FindName("BtnModCamaraDetener").Add_Click({ Detener-CamaraModificacion })
$window.FindName("BtnModCamaraActualizarLista").Add_Click({ Cargar-ListaCamarasModificacion })
$window.FindName("BtnModCamaraRotarIzq").Add_Click({
    $Script:ModCamRotacion = (($Script:ModCamRotacion - 90) + 360) % 360
    Refrescar-DetallesCamaraModificacion
})
$window.FindName("BtnModCamaraRotarDer").Add_Click({
    $Script:ModCamRotacion = ($Script:ModCamRotacion + 90) % 360
    Refrescar-DetallesCamaraModificacion
})
$window.FindName("BtnModCamaraVoltearH").Add_Click({
    $Script:ModCamFlipH = -not $Script:ModCamFlipH
    Refrescar-DetallesCamaraModificacion
})
$window.FindName("BtnModCamaraVoltearV").Add_Click({
    $Script:ModCamFlipV = -not $Script:ModCamFlipV
    Refrescar-DetallesCamaraModificacion
})
$window.FindName("BtnModCamaraRestablecer").Add_Click({
    $Script:ModCamRotacion = 0
    $Script:ModCamFlipH = $false
    $Script:ModCamFlipV = $false
    Refrescar-DetallesCamaraModificacion
})
# Al abrir la pestaña Modificacion por primera vez, carga la lista de camaras
# automaticamente para que el usuario no tenga que pulsar "Actualizar" antes
# de poder elegir una. Tambien: si el usuario se va a OTRA pestaña mientras
# la camara esta encendida, se detiene sola (para no dejar la luz de la
# camara prendida de fondo sin que el usuario lo note).
$Script:_camarasModCargadasUnaVez = $false
$window.FindName("TabControlPrincipal").Add_SelectionChanged({
    $tabActual = $window.FindName("TabControlPrincipal").SelectedItem
    $enModificacion = ($tabActual -and "$($tabActual.Header)" -like "*Modificacion*")
    if ($enModificacion -and -not $Script:_camarasModCargadasUnaVez) {
        $Script:_camarasModCargadasUnaVez = $true
        Cargar-ListaCamarasModificacion
    }
    if (-not $enModificacion -and $Script:ModCamActiva) {
        Detener-CamaraModificacion
    }
})

# --- Pestaña Modificacion: cambio de seccion (Camara / Pantalla / Teclado / Parlante) ---
function Mostrar-SeccionModificacion {
    param([string]$Seccion)
    $window.FindName("PanelModCamara").Visibility = if ($Seccion -eq 'Camara') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelModPantalla").Visibility = if ($Seccion -eq 'Pantalla') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelModTeclado").Visibility = if ($Seccion -eq 'Teclado') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelModParlante").Visibility = if ($Seccion -eq 'Parlante') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelModAlmacenamiento").Visibility = if ($Seccion -eq 'Almacenamiento') { 'Visible' } else { 'Collapsed' }
    if ($Seccion -ne 'Camara' -and $Script:ModCamActiva) { Detener-CamaraModificacion }
}
$window.FindName("CmbSeccionModificacion").Add_SelectionChanged({
    $sel = $window.FindName("CmbSeccionModificacion").SelectedItem
    if (-not $sel) { return }
    switch ($sel.Content) {
        'Camara'         { Mostrar-SeccionModificacion -Seccion 'Camara' }
        'Pantalla'       { Mostrar-SeccionModificacion -Seccion 'Pantalla' }
        'Teclado'        { Mostrar-SeccionModificacion -Seccion 'Teclado' }
        'Parlante'       { Mostrar-SeccionModificacion -Seccion 'Parlante' }
        'Almacenamiento' { Mostrar-SeccionModificacion -Seccion 'Almacenamiento' }
    }
})

# --- Pestaña Modificacion: Pantalla ---
$window.FindName("BtnModPantallaDetectar").Add_Click({ Detectar-PantallaModificacion })
$window.FindName("BtnModPantallaAplicarFrecuencia").Add_Click({
    $cmb = $window.FindName("CmbModPantallaFrecuencia")
    if ($cmb -and $cmb.SelectedItem) { Accion-AplicarFrecuenciaPantalla -TextoFrecuencia "$($cmb.SelectedItem)" }
})
$window.FindName("BtnModPantallaQuitarFrecuencia").Add_Click({
    if ($Script:ModPantallaFrecMaximaDetectada -gt 0) {
        $Script:ModPantallaAutoActivo = $false
        if ($Script:TimerModPantallaEnergia) { $Script:TimerModPantallaEnergia.Stop() }
        $chk = $window.FindName("ChkModPantallaFrecuenciaEnergia")
        if ($chk) { $chk.IsChecked = $false }
        Accion-AplicarFrecuenciaPantalla -TextoFrecuencia "$($Script:ModPantallaFrecMaximaDetectada) Hz"
        Write-Log "Frecuencia fija quitada: se volvio a la maxima nativa ($($Script:ModPantallaFrecMaximaDetectada) Hz)." -Tipo OK
    }
})
$window.FindName("BtnModPantallaGuardarEnergia").Add_Click({
    $cmbCA = $window.FindName("CmbModPantallaFrecuenciaCA")
    $cmbBat = $window.FindName("CmbModPantallaFrecuenciaBateria")
    $chk = $window.FindName("ChkModPantallaFrecuenciaEnergia")
    if ($cmbCA -and $cmbCA.SelectedItem) { $Script:ModPantallaFrecPreferidaCA = [int]("$($cmbCA.SelectedItem)" -replace '[^\d]','') }
    if ($cmbBat -and $cmbBat.SelectedItem) { $Script:ModPantallaFrecPreferidaBateria = [int]("$($cmbBat.SelectedItem)" -replace '[^\d]','') }
    $Script:ModPantallaAutoActivo = [bool]($chk -and $chk.IsChecked)
    if ($Script:ModPantallaAutoActivo) {
        try { $Script:ModPantallaUltimoEstadoEnergia = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString() } catch {}
        if (-not $Script:TimerModPantallaEnergia) {
            $Script:TimerModPantallaEnergia = New-Object System.Windows.Threading.DispatcherTimer
            $Script:TimerModPantallaEnergia.Interval = [TimeSpan]::FromSeconds(5)
            $Script:TimerModPantallaEnergia.Add_Tick({ Revisar-EnergiaPantallaModificacion })
        }
        $Script:TimerModPantallaEnergia.Start()
        Write-Log "Cambio automatico de frecuencia segun fuente de energia activado (cargador: $($Script:ModPantallaFrecPreferidaCA) Hz, bateria: $($Script:ModPantallaFrecPreferidaBateria) Hz)." -Tipo OK
        Show-Aviso "Preferencia guardada. Mientras The Dragon Tool este abierto, la frecuencia cambiara sola segun uses cargador o bateria." "Listo"
    } else {
        if ($Script:TimerModPantallaEnergia) { $Script:TimerModPantallaEnergia.Stop() }
        Write-Log "Cambio automatico de frecuencia segun fuente de energia desactivado." -Tipo INFO
    }
})

# --- Pestaña Modificacion: Teclado ---
Construir-TecladoVisualModificacion
$cmbDestinoTeclado = $window.FindName("CmbModTecladoDestino")
if ($cmbDestinoTeclado) {
    $itemsDestino = New-Object System.Collections.Generic.List[object]
    foreach ($clave in ($Script:EtiquetasTeclasModificacion.Keys | Sort-Object)) {
        $ci = New-Object System.Windows.Controls.ComboBoxItem
        $ci.Content = $Script:EtiquetasTeclasModificacion[$clave]
        $ci.Tag = $clave
        $itemsDestino.Add($ci) | Out-Null
    }
    $cmbDestinoTeclado.ItemsSource = $itemsDestino
}
$window.FindName("BtnModTecladoDetectar").Add_Click({ Detectar-TecladosModificacion })
$window.FindName("BorderModTecladoVisual").Add_PreviewMouseDown({
    $window.FindName("BorderModTecladoVisual").Focus() | Out-Null
})
$window.FindName("BorderModTecladoVisual").Add_PreviewKeyDown({
    param($s, $e)
    $nombreTecla = $e.Key.ToString()
    if ($Script:MapaScanCodes.ContainsKey($nombreTecla)) {
        Seleccionar-TeclaOrigenModificacion -NombreTecla $nombreTecla
    }
    $e.Handled = $true
})
$window.FindName("BtnModTecladoAgregar").Add_Click({ Agregar-MapeoTecladoModificacion })
$window.FindName("BtnModTecladoQuitarUno").Add_Click({
    $grid = $window.FindName("GridModTecladoMapeos")
    if ($grid -and $grid.SelectedItem) {
        $Script:ModTecladoMapeos.Remove($grid.SelectedItem)
        Actualizar-GridMapeosTeclado
    }
})
$window.FindName("BtnModTecladoAplicar").Add_Click({ Accion-AplicarMapeosTeclado })
$window.FindName("BtnModTecladoQuitarTodos").Add_Click({ Accion-QuitarMapeosTeclado })

# --- Pestaña Modificacion: Parlante ---
$window.FindName("BtnModParlanteDetectar").Add_Click({ Detectar-ParlantesModificacion })
$window.FindName("SliderModParlanteVolumen").Add_ValueChanged({
    if ($Script:ModParlanteActualizandoUI) { return }
    $slider = $window.FindName("SliderModParlanteVolumen")
    $txtVol = $window.FindName("TxtModParlanteVolumenValor")
    $nivel = [int]$slider.Value
    if ($txtVol) { $txtVol.Text = "$nivel%" }
    try { Ensure-TipoAudio; [DragonToolAudio]::EstablecerVolumen($nivel / 100.0) } catch {}
})
$window.FindName("ChkModParlanteSilenciar").Add_Click({
    if ($Script:ModParlanteActualizandoUI) { return }
    $chk = $window.FindName("ChkModParlanteSilenciar")
    try { Ensure-TipoAudio; [DragonToolAudio]::EstablecerSilenciado([bool]$chk.IsChecked) } catch {}
})
$window.FindName("ChkModParlanteRefuerzo").Add_Click({
    $chk = $window.FindName("ChkModParlanteRefuerzo")
    if ($chk.IsChecked) { Accion-BoosterVolumenModificacion }
})
$window.FindName("BtnModParlanteInstalarAPO").Add_Click({ Accion-InstalarEqualizerAPO })
$window.FindName("SliderModParlanteAmplificacion").Add_ValueChanged({
    if ($Script:ModParlanteActualizandoUI) { return }
    $slider = $window.FindName("SliderModParlanteAmplificacion")
    $txtValor = $window.FindName("TxtModParlanteAmplificacionValor")
    $pct = [int]$slider.Value
    if ($txtValor) { $txtValor.Text = "$pct%" }
    Accion-AplicarAmplificacionParlante -Porcentaje $pct
})

# --- Pestaña Modificacion: Almacenamiento ---
$window.FindName("BtnModAlmacenamientoDetectar").Add_Click({ Detectar-AlmacenamientoModificacion })
$window.FindName("CmbModAlmacenamientoDispositivo").Add_SelectionChanged({ Mostrar-DetalleAlmacenamientoSeleccionado })
$window.FindName("BtnModAlmacenamientoQuitarSoloLectura").Add_Click({ Accion-QuitarSoloLecturaAlmacenamiento })
$window.FindName("BtnModAlmacenamientoAnalizar").Add_Click({ Accion-AnalizarErroresAlmacenamiento })
$window.FindName("BtnModAlmacenamientoCorregir").Add_Click({ Accion-CorregirErroresAlmacenamiento })
$window.FindName("BtnModAlmacenamientoBuscarFirmware").Add_Click({ Accion-BuscarFirmwareAlmacenamiento })

# Microsoft Store: buscar e instalar
$window.FindName("BtnBuscarStoreWeb").Add_Click({
    $consulta = $window.FindName("TxtBuscarStore").Text
    if ([string]::IsNullOrWhiteSpace($consulta)) { Show-Aviso "Escribe el nombre de la app que buscas." "Busqueda vacia"; return }
    $urlBusqueda = "https://apps.microsoft.com/search?query=$([uri]::EscapeDataString($consulta))"
    Show-VentanaNavegador -Url $urlBusqueda -Titulo "Microsoft Store: $consulta" -TextoRespaldo "$consulta Microsoft Store app"
})
$window.FindName("TxtBuscarStore").Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return') {
        $consulta = $window.FindName("TxtBuscarStore").Text
        if ([string]::IsNullOrWhiteSpace($consulta)) { return }
        $urlBusqueda = "https://apps.microsoft.com/search?query=$([uri]::EscapeDataString($consulta))"
        Show-VentanaNavegador -Url $urlBusqueda -Titulo "Microsoft Store: $consulta" -TextoRespaldo "$consulta Microsoft Store app"
    }
})
$window.FindName("BtnDescargarLinkStore").Add_Click({
    $entrada = $window.FindName("TxtLinkStore").Text
    Accion-InstalarDesdeLinkStore -Entrada $entrada
})

# Archivos ISO: poblar la lista de versiones segun el tipo elegido (Windows/Office)
function Cargar-VersionesISO {
    param([string]$Tipo)
    $cmbVersion = $window.FindName("CmbVersionISO")
    $cmbVersion.Items.Clear()
    foreach ($item in $Script:CatalogoISO[$Tipo]) {
        $cbi = New-Object System.Windows.Controls.ComboBoxItem
        $cbi.Content = $item.Nombre
        $cbi.Tag = $item
        $cmbVersion.Items.Add($cbi) | Out-Null
    }
    if ($cmbVersion.Items.Count -gt 0) { $cmbVersion.SelectedIndex = 0 }
}
$window.FindName("CmbTipoISO").Add_SelectionChanged({
    $sel = $window.FindName("CmbTipoISO").SelectedItem
    if ($sel) { Cargar-VersionesISO -Tipo "$($sel.Content)" }
})

$cmbIdiomaISO = $window.FindName("CmbIdiomaISO")
foreach ($idm in $Script:IdiomasISO) { $cmbIdiomaISO.Items.Add($idm) | Out-Null }
if ($cmbIdiomaISO.Items.Count -gt 0) { $cmbIdiomaISO.SelectedIndex = 0 }
Cargar-VersionesISO -Tipo 'Windows'

$window.FindName("BtnDescargarISO").Add_Click({
    $selVersion = $window.FindName("CmbVersionISO").SelectedItem
    if (-not $selVersion) { Show-Aviso "Selecciona una version primero." "Nada seleccionado"; return }
    Accion-DescargarISO -ItemSeleccionado $selVersion.Tag
})

# Construir dinamicamente el checklist del catalogo de programas
$panelChecklistProg = $window.FindName("PanelChecklistProgramas")
$Script:_checkboxesProgramas = New-Object System.Collections.Generic.List[object]
$categoriasProg = $Script:CatalogoProgramas | ForEach-Object { $_.Categoria } | Select-Object -Unique
foreach ($cat in $categoriasProg) {
    $gb = New-Object System.Windows.Controls.GroupBox
    $gb.Header = $cat
    $gb.Foreground = [System.Windows.Media.Brushes]::White
    $gb.Margin = "0,0,0,10"
    $sp = New-Object System.Windows.Controls.StackPanel
    foreach ($item in ($Script:CatalogoProgramas | Where-Object { $_.Categoria -eq $cat })) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $item.Nombre
        $cb.Foreground = [System.Windows.Media.Brushes]::White
        $cb.Margin = "4"
        $cb.Tag = $item
        $sp.Children.Add($cb) | Out-Null
        $Script:_checkboxesProgramas.Add($cb) | Out-Null
    }
    $gb.Content = $sp
    $panelChecklistProg.Children.Add($gb) | Out-Null
}

$window.FindName("BtnInstalarSeleccionados").Add_Click({
    $seleccionados = @($Script:_checkboxesProgramas | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
    Accion-InstalarCatalogoSeleccionado -Items $seleccionados
})

# Desinstalar programas: un unico boton que abre la ventana con la lista
$window.FindName("BtnVerProgramasInstalados").Add_Click({ Show-VentanaProgramasInstalados })

# --- Selector de categoria: Optimizar Windows ---
function Mostrar-PanelOptimizar {
    param([string]$Categoria)
    $window.FindName("PanelPerfiles").Visibility = if ($Categoria -eq 'Perfiles') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelAcelerarCPU").Visibility = if ($Categoria -eq 'CPU') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelLiberarRAM").Visibility = if ($Categoria -eq 'RAM') { 'Visible' } else { 'Collapsed' }
}
$window.FindName("CmbCategoriaOptimizar").Add_SelectionChanged({
    $sel = $window.FindName("CmbCategoriaOptimizar").SelectedItem
    if (-not $sel) { return }
    switch ($sel.Content) {
        'Perfiles de Optimizacion' { Mostrar-PanelOptimizar -Categoria 'Perfiles' }
        'Acelerar funcionamiento del procesador' { Mostrar-PanelOptimizar -Categoria 'CPU' }
        'Liberar RAM' { Mostrar-PanelOptimizar -Categoria 'RAM' }
    }
})
$window.FindName("BtnAcelerarCPU").Add_Click({ Accion-AcelerarProcesador })
$window.FindName("BtnRamBasica").Add_Click({ Accion-LiberarRAM -Modo 'Basica' })
$window.FindName("BtnRamIntermedia").Add_Click({ Accion-LiberarRAM -Modo 'Intermedia' })
$window.FindName("BtnRamExhaustiva").Add_Click({ Accion-LiberarRAM -Modo 'Exhaustiva' })

# --- Pestaña Controladores (inline, sin ventanas emergentes para la navegacion de paneles) ---
function Mostrar-SeccionControladores {
    param([string]$Seccion)
    $window.FindName("PanelBuscadorControladores").Visibility = if ($Seccion -eq 'Buscador') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelExploradorControladores").Visibility = if ($Seccion -eq 'Explorador') { 'Visible' } else { 'Collapsed' }
}
$window.FindName("CmbSeccionControladores").Add_SelectionChanged({
    $sel = $window.FindName("CmbSeccionControladores").SelectedItem
    if (-not $sel) { return }
    switch ($sel.Content) {
        'Buscador de controladores' { Mostrar-SeccionControladores -Seccion 'Buscador' }
        'Explorador de controladores instalados' { Mostrar-SeccionControladores -Seccion 'Explorador' }
    }
})

# Sub-seccion: Buscador de controladores
$window.FindName("BtnDetectarTodo").Add_Click({
    $window.FindName("TxtDetalleCompleto").Text = "Detectando..."
    $window.FindName("TxtDetalleCompleto").Text = Get-InfoCompleta
    Write-Log "Deteccion completa del equipo realizada." -Tipo OK
})

function Mostrar-PanelBusquedaControladores {
    param([string]$Categoria)
    $window.FindName("PanelGPU").Visibility = if ($Categoria -eq 'GPU') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelPlaca").Visibility = if ($Categoria -eq 'Placa') { 'Visible' } else { 'Collapsed' }
    $window.FindName("PanelLaptop").Visibility = if ($Categoria -eq 'Laptop') { 'Visible' } else { 'Collapsed' }
}
$window.FindName("RbTipoGPU").Add_Checked({ Mostrar-PanelBusquedaControladores -Categoria 'GPU' })
$window.FindName("RbTipoPlaca").Add_Checked({ Mostrar-PanelBusquedaControladores -Categoria 'Placa' })
$window.FindName("RbTipoLaptop").Add_Checked({ Mostrar-PanelBusquedaControladores -Categoria 'Laptop' })

$window.FindName("BtnDetectarGPU").Add_Click({
    $gpus = Get-InfoGPU
    if ($gpus -and $gpus.Count -gt 0) {
        $principal = $gpus | Select-Object -First 1
        $window.FindName("TxtGPUDetectada").Text = ($gpus | ForEach-Object { "$($_.Nombre) [$($_.Fabricante)] - Driver: $($_.DriverVersion)" }) -join "`n"
        $cmb = $window.FindName("CmbFabricanteGPU")
        for ($i = 0; $i -lt $cmb.Items.Count; $i++) { if ($cmb.Items[$i].Content -eq $principal.Fabricante) { $cmb.SelectedIndex = $i } }
        Write-Log "GPU detectada: $($principal.Nombre) ($($principal.Fabricante))" -Tipo OK
    } else { Write-Log "No se pudo detectar la tarjeta de video." -Tipo AVISO }
})
$window.FindName("BtnBuscarGPU").Add_Click({
    $itemSel = $window.FindName("CmbFabricanteGPU").SelectedItem
    $vendor = if ($itemSel) { $itemSel.Content } else { $null }
    if (-not $vendor) { Write-Log "Selecciona un fabricante de video." -Tipo AVISO; return }
    Buscar-DriverGPU -Fabricante $vendor
})

$window.FindName("BtnDetectarPlaca").Add_Click({
    $info = Get-InfoPlaca
    if ($info) {
        $window.FindName("TxtPlacaDetectada").Text = "$($info.Fabricante) $($info.Modelo) (BIOS: $($info.BIOSVersion))"
        Write-Log "Placa detectada: $($info.Fabricante) $($info.Modelo)" -Tipo OK
    } else { Write-Log "No se pudo detectar la placa madre." -Tipo AVISO }
})
$window.FindName("BtnBuscarPlaca").Add_Click({
    $itemMarca = $window.FindName("CmbMarcaPlaca").SelectedItem
    $marca = if ($itemMarca) { $itemMarca.Content } else { $null }
    if (-not $marca) { Write-Log "Selecciona la marca de la placa." -Tipo AVISO; return }
    Buscar-DriverPlaca -Marca $marca
})

$window.FindName("BtnDetectarLaptop").Add_Click({
    $info = Get-InfoEquipo
    if ($info) {
        $window.FindName("TxtLaptopDetectada").Text = "$($info.Fabricante) $($info.Modelo) - Serie: $($info.Serial)"
        Write-Log "Equipo detectado: $($info.Fabricante) $($info.Modelo) (Serie: $($info.Serial))" -Tipo OK
        $cmb = $window.FindName("CmbFabricanteLaptop")
        for ($i = 0; $i -lt $cmb.Items.Count; $i++) { if ($info.Fabricante -and $info.Fabricante -match [regex]::Escape($cmb.Items[$i].Content)) { $cmb.SelectedIndex = $i } }
    } else { Write-Log "No se pudo detectar el modelo/serie del equipo." -Tipo AVISO }
})
$window.FindName("BtnBuscarLaptop").Add_Click({
    $itemSel = $window.FindName("CmbFabricanteLaptop").SelectedItem
    $fab = if ($itemSel) { $itemSel.Content } else { $null }
    if (-not $fab) { Write-Log "Selecciona la marca del portatil." -Tipo AVISO; return }
    Buscar-DriverLaptop -Fabricante $fab
})

# Sub-seccion: Explorador de controladores instalados
# Cada opcion abre su propia ventana (la lista se carga despues de mostrarla, asi abre al instante).
$window.FindName("BtnExpVerTodos").Add_Click({ Show-VentanaListaControladores -Modo 'Todos' })
$window.FindName("BtnExpAtencion").Add_Click({ Show-VentanaListaControladores -Modo 'Atencion' })
$window.FindName("BtnExpFaltantes").Add_Click({ Show-VentanaListaControladores -Modo 'Faltantes' })
$window.FindName("BtnBuscarDriversObsoletos").Add_Click({ Accion-BuscarControladoresObsoletos })
$window.FindName("BtnRepararDriversExp").Add_Click({ Accion-RepararControladores; $Script:_driversExpFecha = $null })
$window.FindName("BtnBackupControladores").Add_Click({ Accion-BackupControladores })
$window.FindName("BtnRestaurarControladoresBackup").Add_Click({ Accion-RestaurarControladoresBackup; $Script:_driversExpFecha = $null })

$window.FindName("BtnTemp").Add_Click({ Accion-LimpiarTemporales })
$window.FindName("BtnPapelera").Add_Click({ Accion-VaciarPapelera })
$window.FindName("BtnWU").Add_Click({ Accion-LimpiarWindowsUpdate })
$window.FindName("BtnCleanmgr").Add_Click({ Accion-LiberadorEspacio })
$window.FindName("BtnOptimizarUnidades").Add_Click({ Accion-OptimizarUnidades })
$window.FindName("BtnChkdsk").Add_Click({ Accion-ProgramarChkDsk })
$window.FindName("BtnStorageSense").Add_Click({ Accion-StorageSense })
$window.FindName("BtnMiniaturas").Add_Click({ Accion-LimpiarMiniaturas })
$window.FindName("BtnVolcados").Add_Click({ Accion-LimpiarVolcadosMemoria })
$window.FindName("BtnDISM").Add_Click({ Accion-LimpiezaDISM })
$window.FindName("BtnCarpetasPesadas").Add_Click({ Accion-CarpetasPesadas })
$window.FindName("BtnWsReset").Add_Click({ Accion-ResetMicrosoftStore })

$window.FindName("BtnResumen").Add_Click({ Accion-ResumenSistema })
$window.FindName("BtnProcesos").Add_Click({ Accion-VerProcesos })
$window.FindName("BtnMemVirtual").Add_Click({ Accion-ConfigurarMemoriaVirtual })
$window.FindName("BtnEfectos").Add_Click({ Accion-EfectosVisuales })
$window.FindName("BtnEnergia").Add_Click({ Accion-PlanAltoRendimiento })
$window.FindName("BtnSysMainOn").Add_Click({ Accion-GestionarSysMain -Modo 'activar' })
$window.FindName("BtnSysMainOff").Add_Click({ Accion-GestionarSysMain -Modo 'desactivar' })
$window.FindName("BtnRevisarInicio").Add_Click({ Accion-RevisarInicio })
$window.FindName("BtnTaskMgr").Add_Click({ Accion-AbrirTaskManager })
$window.FindName("BtnResMon").Add_Click({ Accion-AbrirResMon })
$window.FindName("BtnServicios").Add_Click({ Accion-AbrirServicios })
$window.FindName("BtnPriorizarCPU").Add_Click({ Accion-PriorizarPrimerPlanoBoton })
$window.FindName("BtnBackgroundAppsOff").Add_Click({ Accion-BackgroundAppsOffBoton })

$window.FindName("BtnDevMgmt").Add_Click({ Accion-AbrirAdministradorDispositivos })
$window.FindName("BtnUpdatesOpc").Add_Click({ Accion-AbrirActualizacionesOpcionales })
$window.FindName("BtnDriversAuto").Add_Click({ Accion-ActualizarControladoresAuto })
$window.FindName("BtnPausarUpdates").Add_Click({ Accion-PausarActualizaciones7Dias })
$window.FindName("BtnDeshabilitarUpdates").Add_Click({ Accion-DeshabilitarWindowsUpdate })
$window.FindName("BtnReanudarUpdates").Add_Click({ Accion-ReanudarActualizaciones })
$window.FindName("BtnForzarUpdate").Add_Click({ Accion-ForzarBusquedaUpdates })
$window.FindName("BtnHistorialUpdates").Add_Click({ Accion-HistorialUpdates })
$window.FindName("BtnRepararWU").Add_Click({ Accion-RepararWindowsUpdate })
$window.FindName("BtnDefenderUpdate").Add_Click({ Accion-ActualizarDefenderFirmas })

$window.FindName("BtnDNS").Add_Click({ Accion-VaciarDNS })
$window.FindName("BtnRenovarIP").Add_Click({ Accion-RenovarIP })
$window.FindName("BtnDefender").Add_Click({ Accion-AnalisisDefender })
$window.FindName("BtnVerAdaptadores").Add_Click({ Accion-VerAdaptadoresRed })
$window.FindName("BtnReiniciarRed").Add_Click({ Accion-ReiniciarAdaptadoresRed })
$window.FindName("BtnResetWinsock").Add_Click({ Accion-ResetWinsockTCPIP })
$window.FindName("BtnVerIP").Add_Click({ Accion-VerIP })
$window.FindName("BtnDefenderFull").Add_Click({ Accion-AnalisisDefenderCompleto })
$window.FindName("BtnFirewallEstado").Add_Click({ Accion-EstadoFirewall })

$window.FindName("BtnExplorer").Add_Click({ Accion-ReiniciarExplorer })
$window.FindName("BtnPuntoRestauracion").Add_Click({ Accion-CrearPuntoRestauracion })
$window.FindName("BtnAbrirRestaurar").Add_Click({ Accion-AbrirRestaurarSistema })
$window.FindName("BtnSFC").Add_Click({ Accion-VerificarArchivosSistema })
$window.FindName("BtnDISMRestore").Add_Click({ Accion-RepararImagenWindows })
$window.FindName("BtnVariablesEntorno").Add_Click({ Accion-VariablesEntorno })
$window.FindName("BtnInformeEnergia").Add_Click({ Accion-InformeEnergia })
$window.FindName("BtnReiniciarEquipo").Add_Click({ Accion-ReiniciarEquipo })
$window.FindName("BtnApagarEquipo").Add_Click({ Accion-ApagarEquipo })

$window.FindName("BtnBajaLatenciaOn").Add_Click({ Accion-BajaLatenciaOn })
$window.FindName("BtnBajaLatenciaOff").Add_Click({ Accion-BajaLatenciaOff })
$window.FindName("BtnMenuClasico").Add_Click({ Accion-MenuContextualClasico })
$window.FindName("BtnMenuModerno").Add_Click({ Accion-MenuContextualModerno })
$window.FindName("BtnTaskbarIzquierda").Add_Click({ Accion-TaskbarIzquierda })
$window.FindName("BtnTaskbarCentrada").Add_Click({ Accion-TaskbarCentrada })
$window.FindName("BtnSegundosOn").Add_Click({ Accion-SegundosRelojOn })
$window.FindName("BtnSegundosOff").Add_Click({ Accion-SegundosRelojOff })
$window.FindName("BtnWidgetsOff").Add_Click({ Accion-WidgetsOff })
$window.FindName("BtnWidgetsOn").Add_Click({ Accion-WidgetsOn })
$window.FindName("BtnFinalizarTarea").Add_Click({ Accion-FinalizarTareaTaskbar })
$window.FindName("BtnSnapOff").Add_Click({ Accion-SnapLayoutsOff })
$window.FindName("BtnSnapOn").Add_Click({ Accion-SnapLayoutsOn })
$window.FindName("BtnConfigGraficos").Add_Click({ Accion-AbrirConfigGraficos })
$window.FindName("BtnEstadoActivacion").Add_Click({ Accion-VerEstadoActivacion })

$window.FindName("BtnCambiarFondo").Add_Click({ Accion-CambiarFondoPantalla })
$window.FindName("BtnTemaOscuro").Add_Click({ Accion-TemaOscuroOn })
$window.FindName("BtnTemaClaro").Add_Click({ Accion-TemaClaroOn })
$window.FindName("BtnAbrirPersonalizacion").Add_Click({ Accion-AbrirConfigPersonalizacion })
$window.FindName("BtnAbrirPantallaBloqueoConfig").Add_Click({ Accion-AbrirConfigPantallaBloqueo })
$window.FindName("BtnAbrirSonidos").Add_Click({ Accion-AbrirConfigSonidos })
$window.FindName("BtnAbrirCursor").Add_Click({ Accion-AbrirConfigCursor })

# --- Pestaña BSOD ---
$window.FindName("BtnActualizarBSODTab").Add_Click({ Cargar-DatosBSODTab })
$window.FindName("BtnExportarBSOD").Add_Click({ Accion-ExportarHistorialBSOD })
$window.FindName("BtnConfigVolcado").Add_Click({ Accion-ConfigVolcadoMemoria })
$window.FindName("BtnMonitorConfiabilidad").Add_Click({ Accion-AbrirMonitorConfiabilidad })
$window.FindName("BtnDiagMemoriaTab").Add_Click({ Accion-DiagnosticoMemoriaWindows })
$window.FindName("BtnAbrirMinidumpTab").Add_Click({ Accion-AbrirCarpetaMinidump })
$window.FindName("BtnDriversRecientes").Add_Click({ Accion-VerControladoresRecientes })
$window.FindName("BtnSFCTab").Add_Click({ Accion-VerificarArchivosSistema })
Cargar-DatosBSODTab

# --- Pestaña Diagnosticar equipo ---
$window.FindName("BtnProbarCamara").Add_Click({ Show-PruebaCamara })
$window.FindName("BtnProbarTeclado").Add_Click({ Show-PruebaTeclado })
$window.FindName("BtnProbarMicrofono").Add_Click({ Show-PruebaMicrofono })
$window.FindName("BtnProbarAudioIzq").Add_Click({ Accion-ProbarAudioCanal -Canal 'Izquierdo' })
$window.FindName("BtnProbarAudioDer").Add_Click({ Accion-ProbarAudioCanal -Canal 'Derecho' })
$window.FindName("BtnProbarAudioAmbos").Add_Click({ Accion-ProbarAudioCanal -Canal 'Ambos' })
$window.FindName("BtnProbarPantalla").Add_Click({ Show-PruebaPantalla })
$window.FindName("BtnDetallesPantalla").Add_Click({ Accion-VerDetallesPantalla })
$window.FindName("BtnProbarRAM").Add_Click({ Show-SeleccionPruebaRAM })
$window.FindName("BtnProbarAlmacenamiento").Add_Click({ Accion-ProbarAlmacenamiento })
$window.FindName("BtnVelocidadDisco").Add_Click({ Accion-ProbarVelocidadDisco })
$window.FindName("BtnProbarVentiladores").Add_Click({ Accion-ProbarVentiladores })
$window.FindName("BtnProbarGrafica").Add_Click({ Accion-ProbarGraficaDiag })
$window.FindName("BtnProbarMouse").Add_Click({ Show-PruebaMouse })
$window.FindName("BtnProbarBateria").Add_Click({ Accion-ProbarBateria })
$window.FindName("BtnProbarRed").Add_Click({ Accion-ProbarRed })
$window.FindName("BtnProbarTemperatura").Add_Click({ Accion-ProbarTemperaturaCPU })
$window.FindName("BtnProbarArranque").Add_Click({ Accion-ProbarTiempoArranque })
$window.FindName("BtnProbarBluetooth").Add_Click({ Accion-ProbarBluetooth })
$window.FindName("BtnProbarUSB").Add_Click({ Accion-ProbarPuertosUSB })
$window.FindName("BtnDiagCompleto").Add_Click({ Accion-DiagnosticoCompletoEquipo })

# --- Pestaña Registro de errores ---
function Cargar-RegistroErrores {
    $gridErr = $window.FindName("GridRegistroErrores")
    $filtroCategoria = $window.FindName("CmbFiltroCategoriaError").SelectedItem
    $textoBusqueda = $window.FindName("TxtBuscarError").Text

    $items = $Script:RegistroErrores
    if ($filtroCategoria -and $filtroCategoria.Content -ne 'Todas') {
        $items = $items | Where-Object { $_.Categoria -eq $filtroCategoria.Content }
    }
    if (-not [string]::IsNullOrWhiteSpace($textoBusqueda)) {
        $items = $items | Where-Object {
            $_.Mensaje -match [regex]::Escape($textoBusqueda) -or $_.Origen -match [regex]::Escape($textoBusqueda)
        }
    }
    $listaOrdenada = @($items | Sort-Object Hora -Descending)
    $gridErr.ItemsSource = $listaOrdenada

    $totalErrores = @($Script:RegistroErrores | Where-Object { $_.Tipo -eq 'ERROR' }).Count
    $totalAvisos = @($Script:RegistroErrores | Where-Object { $_.Tipo -eq 'AVISO' }).Count
    $window.FindName("TxtResumenErrores").Text = "Mostrando $($listaOrdenada.Count) de $($Script:RegistroErrores.Count) registro(s) totales ($totalErrores error(es), $totalAvisos aviso(s))."
}

$window.FindName("BtnActualizarErrores").Add_Click({ Cargar-RegistroErrores })
$window.FindName("CmbFiltroCategoriaError").Add_SelectionChanged({ Cargar-RegistroErrores })
$window.FindName("TxtBuscarError").Add_TextChanged({ Cargar-RegistroErrores })

$window.FindName("BtnCopiarErrores").Add_Click({
    if ($Script:RegistroErrores.Count -eq 0) { Show-Aviso "No hay errores registrados." "Registro vacio"; return }
    $texto = ($Script:RegistroErrores | ForEach-Object { "$($_.Hora) [$($_.Tipo)] $($_.Categoria) - $($_.Origen): $($_.Mensaje)" }) -join "`r`n"
    try {
        Set-Clipboard -Value $texto -ErrorAction Stop
        Write-Log "Registro de errores copiado al portapapeles ($($Script:RegistroErrores.Count) entrada(s))." -Tipo OK
    } catch {
        Write-Log "No se pudo copiar al portapapeles (puede estar en uso por otro programa): $($_.Exception.Message)" -Tipo AVISO
    }
})

$window.FindName("BtnExportarErrores").Add_Click({
    if ($Script:RegistroErrores.Count -eq 0) { Show-Aviso "No hay errores registrados." "Registro vacio"; return }
    Add-Type -AssemblyName System.Windows.Forms
    $dialogo = New-Object System.Windows.Forms.SaveFileDialog
    $dialogo.Title = "Guardar registro de errores"
    $dialogo.Filter = "Archivo de texto (*.txt)|*.txt"
    $dialogo.FileName = "DragonTool_RegistroErrores_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    if ($dialogo.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $texto = ($Script:RegistroErrores | ForEach-Object { "$($_.Hora) [$($_.Tipo)] $($_.Categoria) - $($_.Origen): $($_.Mensaje)" }) -join "`r`n"
            Set-Content -Path $dialogo.FileName -Value $texto -Encoding UTF8
            Write-Log "Registro de errores exportado a: $($dialogo.FileName)" -Tipo OK
            Show-Aviso "Registro exportado correctamente." "Exportado"
        } catch {
            Write-Log "No se pudo exportar el registro de errores: $($_.Exception.Message)" -Tipo ERROR
        }
    }
})

$window.FindName("BtnLimpiarErrores").Add_Click({
    if ($Script:RegistroErrores.Count -eq 0) { return }
    if (-not (Show-Confirm "¿Vaciar por completo el registro de errores? Esta accion no se puede deshacer.")) { return }
    $Script:RegistroErrores.Clear()
    Cargar-RegistroErrores
})

Cargar-RegistroErrores

# --- Panel de Inicio: acciones rapidas y actualizacion periodica ---
$window.FindName("BtnInicioLimpiarTemp").Add_Click({ Accion-LimpiarTemporales; Actualizar-PanelInicio })
$window.FindName("BtnInicioLiberarRAM").Add_Click({ Accion-LiberarRAM -Modo 'Basica'; Actualizar-PanelInicio })
$window.FindName("BtnInicioPerfilBajo").Add_Click({ Perfil-BajoConsumo; Actualizar-PanelInicio })
$window.FindName("BtnInicioDiagnostico").Add_Click({ Accion-DiagnosticoCompletoEquipo })
$window.FindName("BtnInicioActualizar").Add_Click({ Actualizar-PanelInicio })

$Script:TimerInicio = New-Object System.Windows.Threading.DispatcherTimer
$Script:TimerInicio.Interval = [TimeSpan]::FromSeconds(3)
$Script:TimerInicio.Add_Tick({ Actualizar-PanelInicio })
$Script:TimerInicio.Start()
Actualizar-PanelInicio

$window.Dispatcher.add_UnhandledException({
    param($s, $e)
    try { Write-Log "Error inesperado no controlado: $($e.Exception.Message)" -Tipo ERROR } catch {}
    $e.Handled = $true
})

# Detiene el timer del panel de Inicio y la camara de la pestaña
# Modificacion (si estaba encendida) al cerrar la ventana principal, para
# no dejar recursos abiertos de fondo.
$window.Add_Closed({
    try { if ($Script:TimerInicio) { $Script:TimerInicio.Stop() } } catch {}
    try { if ($Script:ModCamActiva) { Detener-CamaraModificacion } } catch {}
    try { if ($Script:TimerModPantallaEnergia) { $Script:TimerModPantallaEnergia.Stop() } } catch {}
})

# --- Navegacion lateral neon (reemplaza la franja de pestañas) ----------
# Cada TabItem del TabControl (oculto) se convierte automaticamente en un
# boton redondeado semitransparente del panel izquierdo; si en el futuro se
# agrega otra pestaña, aparece sola en el menu. El panel arranca OCULTO, se
# despliega con el boton "MENU" y se vuelve a ocultar solo al elegir una opcion.
$Script:PanelNavAbierto = $false   # arranca oculto; solo se despliega con el boton MENU

function Mostrar-PanelLateral {
    try { Animar-EntradaElementos -Elementos $window.FindName("ContenedorNav").Children -DesdeX -38 -PasoMs 38 -DuracionMs 320 } catch {}
    $panel = $window.FindName("PanelLateral")
    $velo = $window.FindName("VeloNav")
    $desplaza = $window.FindName("DesplazaPanel")
    if (-not $panel -or -not $velo -or -not $desplaza) { return }
    $Script:PanelNavAbierto = $true
    $panel.Visibility = [System.Windows.Visibility]::Visible
    $velo.Visibility = [System.Windows.Visibility]::Visible
    $facil = New-Object System.Windows.Media.Animation.CubicEase
    $facil.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $animPanel = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animPanel.To = 0
    $animPanel.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(280))
    $animPanel.EasingFunction = $facil
    $desplaza.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $animPanel)
    $animVelo = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animVelo.To = 1
    $animVelo.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(280))
    $velo.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animVelo)
}

function Ocultar-PanelLateral {
    if (-not $Script:PanelNavAbierto) { return }
    $panel = $window.FindName("PanelLateral")
    $velo = $window.FindName("VeloNav")
    $desplaza = $window.FindName("DesplazaPanel")
    if (-not $panel -or -not $velo -or -not $desplaza) { return }
    $Script:PanelNavAbierto = $false
    $facil = New-Object System.Windows.Media.Animation.CubicEase
    $facil.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn
    $animPanel = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animPanel.To = -($panel.ActualWidth + 30)
    $animPanel.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(230))
    $animPanel.EasingFunction = $facil
    # Al terminar la animacion se colapsa todo (deja de dibujarse y de recibir foco),
    # salvo que mientras tanto el usuario haya vuelto a abrir el panel.
    $animPanel.add_Completed({
        if (-not $Script:PanelNavAbierto) {
            $window.FindName("PanelLateral").Visibility = [System.Windows.Visibility]::Collapsed
            $window.FindName("VeloNav").Visibility = [System.Windows.Visibility]::Collapsed
        }
    })
    $desplaza.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $animPanel)
    $animVelo = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animVelo.To = 0
    $animVelo.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(230))
    $velo.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animVelo)
}

function Sincronizar-NavLateral {
    $tc = $window.FindName("TabControlPrincipal")
    $contenedor = $window.FindName("ContenedorNav")
    $titulo = $window.FindName("TxtSeccionActual")
    if (-not $tc -or -not $contenedor) { return }
    $seleccionada = $tc.SelectedItem
    if (-not $seleccionada) { return }
    if ($titulo) { $titulo.Text = "$($seleccionada.Header)" }
    foreach ($rb in $contenedor.Children) {
        $rb.IsChecked = [bool]($rb.Tag -eq $seleccionada)
    }
}

try {
    $tcNav = $window.FindName("TabControlPrincipal")
    $contenedorNav = $window.FindName("ContenedorNav")
    $estiloNav = $window.FindResource("NeonNavButton")
    foreach ($pestanaNav in $tcNav.Items) {
        $rbNav = New-Object System.Windows.Controls.RadioButton
        $rbNav.Style = $estiloNav
        $rbNav.Content = "$($pestanaNav.Header)"
        $rbNav.GroupName = "NavPrincipal"
        $rbNav.Tag = $pestanaNav
        $rbNav.Add_Click({
            param($remitenteNav, $eventoNav)
            $destino = $remitenteNav.Tag
            if ($destino) { $window.FindName("TabControlPrincipal").SelectedItem = $destino }
            Ocultar-PanelLateral
        })
        [void]$contenedorNav.Children.Add($rbNav)
    }

    $window.FindName("BtnMenuLateral").Add_Click({
        if ($Script:PanelNavAbierto) { Ocultar-PanelLateral } else { Mostrar-PanelLateral }
    })
    $window.FindName("BtnCerrarNav").Add_Click({ Ocultar-PanelLateral })
    $window.FindName("VeloNav").Add_MouseLeftButtonDown({ Ocultar-PanelLateral })
    $window.Add_PreviewKeyDown({
        param($remitenteTecla, $eventoTecla)
        if ($eventoTecla.Key -eq [System.Windows.Input.Key]::Escape -and $Script:PanelNavAbierto) {
            Ocultar-PanelLateral
            $eventoTecla.Handled = $true
        }
    })
    # Mantiene el titulo de la barra y el boton marcado en sincronia con la pestaña activa
    # (SelectionChanged tambien llega burbujeando desde ComboBox internos; es inocuo).
    $tcNav.Add_SelectionChanged({
        param($remitenteTab, $eventoTab)
        # SelectionChanged tambien llega burbujeando desde los ComboBox internos: solo animar si cambia la pestaña
        if ($eventoTab.OriginalSource -eq $remitenteTab) { Animar-CambioPestana }
        Sincronizar-NavLateral
    })
    Sincronizar-NavLateral
} catch {
    Write-Log "No se pudo construir el panel lateral de navegacion: $($_.Exception.Message)" -Tipo ERROR
}

# Animaciones de entrada de las secciones (paneles) y latido del logo
try {
    $nPaneles = Registrar-AnimacionesPaneles -Raiz $window
    Animar-Respiracion -Elemento $window.FindName("ImgLogo") -Escala 1.08 -Segundos 2.4
} catch {
    Write-Log "No se pudieron preparar las animaciones de las secciones: $($_.Exception.Message)" -Tipo AVISO
}

# Animacion del borde neon: un unico giro continuo del pincel compartido mueve
# los colores alrededor de todos los botones y bordes a la vez (muy barato de dibujar).
try {
    $pincelNeon = $window.FindResource("NeonBrush")
    if (-not (Animar-PincelNeon -Pincel $pincelNeon)) { throw "el pincel no admite animacion" }
} catch {
    Write-Log "No se pudo animar el borde neon (se muestra estatico): $($_.Exception.Message)" -Tipo AVISO
}

# --- Ajuste automatico al tamaño de pantalla --------------------------
# La ventana se diseño para 1060x780, pero en pantallas mas chicas (muchas
# laptops de 14" traen 1366x768, y algunas incluso menos) ese alto no
# entraba completo junto con la barra de tareas de Windows, y la ventana
# quedaba cortada contra el borde inferior. Se ajusta el tamaño al AREA DE
# TRABAJO real de la pantalla (la resolucion menos la barra de tareas), con
# un margen, y nunca se agranda mas alla del tamaño de diseño original en
# pantallas grandes. Cada pestaña ya tiene su propio ScrollViewer, asi que
# si aun con el ajuste algo no entra completo, se puede desplazar sin perder
# nada de la interfaz.
try {
    $areaTrabajo = [System.Windows.SystemParameters]::WorkArea
    $anchoDiseno = $window.Width
    $altoDiseno = $window.Height
    $window.MinWidth = 760
    $window.MinHeight = 520
    $anchoFinal = [Math]::Min($anchoDiseno, $areaTrabajo.Width * 0.94)
    $altoFinal = [Math]::Min($altoDiseno, $areaTrabajo.Height * 0.92)
    $window.Width = [Math]::Max($anchoFinal, $window.MinWidth)
    $window.Height = [Math]::Max($altoFinal, $window.MinHeight)
    # Si ni siquiera al tamaño minimo entra en el area de trabajo (pantallas
    # muy pequeñas), se maximiza para aprovechar todo el espacio disponible
    # en vez de quedar con bordes cortados fuera de la pantalla.
    if ($window.MinWidth -gt $areaTrabajo.Width -or $window.MinHeight -gt $areaTrabajo.Height) {
        $window.WindowState = [System.Windows.WindowState]::Maximized
    }
} catch {
    # Si por algun motivo no se puede leer el area de trabajo de la pantalla,
    # se deja el tamaño de diseño original tal cual (mismo comportamiento de
    # antes de este ajuste).
}

Write-Log "The Dragon Tool listo. Creado por $Script:Autor." -Tipo OK
$window.ShowDialog() | Out-Null
