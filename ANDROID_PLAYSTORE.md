# AQUABRI para Android — preparación

Este proyecto es una envoltura nativa **Capacitor 8** de la interfaz web de AQUABRI. Mantiene los datos en el Supabase original, pero **no crea ni modifica tablas**. No incluye claves de firma.

## APK de prueba
En GitHub: Actions > AQUABRI Android - APK de pruebas > Run workflow. Descargar el artifact `aquabri-android-apk-pruebas` cuando finalice correctamente. Un APK debug sirve para probar en Android, **no** para subir a Google Play.

En Windows con Node 22, Android Studio y Android SDK API 36 instalados:
```
npm install
npm run android:init
npx cap open android
```

## Antes de publicar en Google Play
- Auditar RLS y permisos de Supabase, autenticación, exposición de credenciales y cobros.
- Probar navegación, recuperación de conexión, login, GPS/ubicación (si se utiliza), compartir/descargar comprobantes, Android WebView y permisos.
- Confirmar el **applicationId** definitivo `com.aquabri.ventas` antes de la primera publicación, porque luego queda vinculado al registro.
- Generar un **Android App Bundle (.aab) de release firmado** con una clave protegida y Play App Signing, configurar versiones y probar instalación.
- Preparar política de privacidad, ficha de Play Store, capturas, declaración de seguridad de datos y requisitos de acceso a pruebas.
- Este build usa archivos web locales: hay que recompilar para distribuir cambios de AQUABRI. No introducir `server.url` de producción para simular una app nativa.
- Las CDN remotas para Supabase y otras librerías necesitan conexión; deben auditarse/empacarse antes de release para funcionamiento confiable.

Este repositorio no publica automáticamente en Play Store ni contiene archivos de firma.
