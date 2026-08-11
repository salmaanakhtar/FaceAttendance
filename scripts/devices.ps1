# List Android devices/AVDs.
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$emu = "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe"
"--- adb devices ---"
& $adb devices
"--- AVDs ---"
& $emu -list-avds
