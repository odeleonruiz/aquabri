'use strict';
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const pngToIco = require('png-to-ico');

(async () => {
  const src = path.resolve(__dirname, '..', 'assets', 'colibri-marca.webp');
  const outDir = path.resolve(__dirname, 'build');
  fs.mkdirSync(outDir, { recursive: true });
  const square = await sharp(src).resize(512, 512, { fit: 'contain', background: { r: 8, g: 76, b: 169, alpha: 1 } }).png().toBuffer();
  fs.writeFileSync(path.join(outDir, 'icon.png'), square);
  const ico = await pngToIco(square);
  fs.writeFileSync(path.join(outDir, 'icon.ico'), ico);
  console.log('Ícono de Aquabri creado.');
})().catch(err => { console.error(err); process.exitCode = 1; });
