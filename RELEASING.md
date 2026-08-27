# Como gerar uma release do Darkmoon

Processo **manual** (não há CI). Alvo: Windows x64. O binário é distribuído
como um `.zip` portátil anexado a uma GitHub Release — a pasta `dist/` é
ignorada pelo git, o artefato só vive no GitHub.

Todos os comandos são para **PowerShell**, rodados a partir da raiz do repo
(`d:\Documentos\GitHub\darkmoon`).

---

## Pré-requisitos (uma vez)

- **Flutter SDK em `D:\flutter`** com o patch do Visual Studio 18 já aplicado
  (ver `flutter_app/README.md` → "Visual Studio 18"). Se o build nativo falhar
  com gerador CMake errado, é esse patch que precisa ser reaplicado.
- **`gh` autenticado**: `gh auth status` deve mostrar login em
  `github.com/vinioliveiras/darkmoon`.
- Deixar o Flutter no PATH da sessão:
  ```powershell
  $env:Path += ";D:\flutter\bin"
  ```

---

## Passo a passo

### 1. Escolher a versão (SemVer `vX.Y.Z`)

- **Patch** (`v1.1.0` → `v1.1.1`): só correções de bug, sem mudança de
  comportamento visível.
- **Minor** (`v1.1.0` → `v1.2.0`): novos recursos ou mudança perceptível no
  resultado de render / no fluxo.
- **Major** (`v1.1.0` → `v2.0.0`): quebra de compatibilidade (ex.: presets
  antigos deixam de importar igual).

Ver a última publicada:
```powershell
git tag --list "v*" | Sort-Object { [version]($_ -replace '^v') } | Select-Object -Last 1
gh release list -L 3
```

### 2. Levar o trabalho para a `master`

Working tree limpo primeiro (`git status`). Com a branch de trabalho já
mergeada/rebaseada e à frente da master, é fast-forward:

```powershell
git checkout master
git pull --ff-only
git merge --ff-only <branch-de-trabalho>
```

Se o `--ff-only` falhar (a master andou), rebaseie a branch antes:
`git checkout <branch>; git rebase master; git checkout master; git merge --ff-only <branch>`.

### 3. Bump da versão (dois lugares)

1. `flutter_app/pubspec.yaml`, linha `version:` — subir o nome e
   incrementar o build number:

   ```
   version: 1.2.0+1     # era 1.1.0+1
   ```

2. `flutter_app/lib/widgets/about_dialog.dart`, `darkmoonAppVersion` — é o
   que aparece no diálogo "Sobre":

   ```dart
   const String darkmoonAppVersion = 'v1.2.0';
   ```

### 4. Verificar

```powershell
cd flutter_app
flutter analyze          # tem que dar "No issues found!"
flutter test             # todos os testes verdes
cd ..
```

### 5. Commit + push da master

```powershell
git add flutter_app/pubspec.yaml
git commit -m "Release v1.2.0

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push origin master
```

### 6. Build Windows release

```powershell
cd flutter_app
flutter build windows --release
cd ..
```

Saída: `flutter_app\build\windows\x64\runner\Release\` (contém `darkmoon.exe`,
as DLLs e a pasta `data\`).

### 7. Empacotar o `.zip`

O zip contém o **conteúdo** da pasta `Release` na raiz (não a pasta em si):

```powershell
$ver = "v1.2.0"
$rel = "flutter_app\build\windows\x64\runner\Release"
$out = "dist\darkmoon-windows-$ver.zip"
New-Item -ItemType Directory -Force dist | Out-Null
if (Test-Path $out) { Remove-Item $out }
Compress-Archive -Path (Join-Path $rel '*') -DestinationPath $out -CompressionLevel Optimal
Get-Item $out | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}
```

### 8. Tag + push

```powershell
git tag v1.2.0
git push origin v1.2.0
```

### 9. Criar a GitHub Release

```powershell
gh release create v1.2.0 dist\darkmoon-windows-v1.2.0.zip `
  --title "Darkmoon v1.2.0" `
  --notes "Resumo curto do que mudou.

- item 1
- item 2

**Download:** darkmoon-windows-v1.2.0.zip — extrair e rodar darkmoon.exe (Windows x64)."
```

Para gerar a lista de mudanças a partir dos commits:
```powershell
git log --oneline v1.1.0..v1.2.0
```

### 10. Conferir

```powershell
gh release view v1.2.0
```

Baixar o zip em outra pasta, extrair, rodar `darkmoon.exe` e abrir uma pasta
de RAWs para dar um smoke test rápido.

---

## Assinatura de código (opcional)

Se houver certificado de code-signing configurado, assinar **antes** do passo 7:

```powershell
signtool sign /fd SHA256 /tr http://timestamp.sectigo.com /td SHA256 /a `
  "flutter_app\build\windows\x64\runner\Release\darkmoon.exe"
```

---

## Script único (copiar, ajustar `$ver` e a branch)

```powershell
$env:Path += ";D:\flutter\bin"
$ver   = "v1.2.0"                     # <-- ajustar
$name  = $ver.TrimStart('v')
$branch = "claude/minha-branch"       # <-- ajustar

git checkout master
git pull --ff-only
git merge --ff-only $branch

# bump manual antes de continuar:
#   flutter_app/pubspec.yaml           -> version: $name+1
#   flutter_app/lib/widgets/about_dialog.dart -> darkmoonAppVersion = '$ver'
Read-Host "Edite pubspec.yaml e about_dialog.dart e tecle Enter"

Push-Location flutter_app
flutter analyze
flutter test
flutter build windows --release
Pop-Location

git add flutter_app/pubspec.yaml flutter_app/lib/widgets/about_dialog.dart
git commit -m "Release $ver`n`nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push origin master

$rel = "flutter_app\build\windows\x64\runner\Release"
$out = "dist\darkmoon-windows-$ver.zip"
New-Item -ItemType Directory -Force dist | Out-Null
if (Test-Path $out) { Remove-Item $out }
Compress-Archive -Path (Join-Path $rel '*') -DestinationPath $out -CompressionLevel Optimal

git tag $ver
git push origin $ver

gh release create $ver $out --title "Darkmoon $ver" --notes "Ver git log --oneline para as mudanças."
gh release view $ver
```
