'use strict';
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const pngToIco = require('png-to-ico');

(async () => {
  // Esta carita es el ícono elegido por el dueño de Aquabri.
  // NO usar assets/colibri-marca.webp, que contiene el logo completo.
  const src = path.resolve(__dirname, 'icon-face.jpg');
  const outDir = path.resolve(__dirname, 'build');
  fs.mkdirSync(outDir, { recursive: true });
  const square = await sharp(src).resize(256, 256, { fit: 'cover' }).png().toBuffer();
  fs.writeFileSync(path.join(outDir, 'icon.png'), square);
  fs.writeFileSync(path.join(outDir, 'icon.ico'), await pngToIco(square));
  console.log('Carita del colibrí configurada como icono para Windows.');
})().catch(err => { console.error(err); process.exitCode = 1; });
