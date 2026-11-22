// Compilación aislada para equipos antiguos con Windows 8.1.
import fs from 'node:fs';
const file = new URL('./package.json', import.meta.url);
const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
pkg.version = '1.0.2';
pkg.description = 'Edición heredada de Aquabri System para Windows 8.1';
pkg.devDependencies.electron = '22.3.27';
pkg.devDependencies['electron-builder'] = '24.13.3';
pkg.build.appId = 'com.aquabri.system.win81';
pkg.build.productName = 'Aquabri System Windows 8.1';
pkg.build.win.target = [{target:'nsis',arch:['ia32']}];
pkg.build.win.artifactName = 'Aquabri-System-Win81-Setup-${version}.${ext}';
pkg.build.nsis.shortcutName = 'Aquabri System (Windows 8.1)';
pkg.build.nsis.include = undefined;
pkg.scripts['dist:win81'] = 'npm run prepare:icon && electron-builder --win nsis --ia32';
fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + '\n');
console.log('Configurada versión 1.0.2 (Electron 22.3.27, Windows x86/32-bit).');
