# Aquabri System — Windows

Aplicación de escritorio creada con Electron. Abre https://odeleonruiz.github.io/aquabri/ en una ventana independiente, maximizada y sin consola. Los datos siguen en la infraestructura actual de Aquabri; este instalador no incorpora ni copia la base de datos.

## Compilar en Windows
1. Instalar Node.js LTS.
2. En esta carpeta ejecutar `npm install`.
3. Ejecutar `npm run dist:win`.
4. El instalador queda en `dist/Aquabri-System-Setup-1.0.0.exe`.

También se puede descargar desde la sección Actions del repositorio tras ejecutar el flujo **Aquabri Windows Installer**.

**Nota:** Se requiere internet para cargar Aquabri. El instalador no está firmado; Windows SmartScreen puede mostrar un aviso de editor desconocido. Las modificaciones de la web se ven al reiniciar o refrescar la aplicación, aunque actualizaciones del propio instalador siguen siendo independientes.
