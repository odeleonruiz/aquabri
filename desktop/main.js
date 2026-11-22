'use strict';
const { app, BrowserWindow, shell, session, nativeImage } = require('electron');
const path = require('path');

const APP_URL = 'https://odeleonruiz.github.io/aquabri/';
const APP_ORIGIN = new URL(APP_URL).origin;
let mainWindow;

function allowedNavigation(raw) {
  try {
    const url = new URL(raw);
    return url.protocol === 'https:' && url.origin === APP_ORIGIN && url.pathname.startsWith('/aquabri/');
  } catch { return false; }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    title: 'Aquabri System',
    width: 1280,
    height: 850,
    minWidth: 380,
    minHeight: 600,
    autoHideMenuBar: true,
    show: false,
    backgroundColor: '#073f99',
    icon: path.join(__dirname, 'build', 'icon.ico'),
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      spellcheck: false
    }
  });
  mainWindow.setMenuBarVisibility(false);
  mainWindow.maximize();
  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!allowedNavigation(url)) {
      event.preventDefault();
      if (/^https:\/\//i.test(url)) shell.openExternal(url);
    }
  });
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https:\/\//i.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('did-fail-load', (_event, errorCode, description, validatedURL, isMainFrame) => {
    if (isMainFrame && errorCode !== -3) console.error('No se pudo cargar Aquabri:', description, validatedURL);
  });
  mainWindow.loadURL(APP_URL);
}

app.whenReady().then(() => {
  // Evita conceder permisos de sistema a contenido web sin consentimiento explícito.
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
