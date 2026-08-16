[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
Set-Location D:\Navigation\client
flutter run --dart-define-from-file=config.local.json -d 100.112.176.99:5555 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
