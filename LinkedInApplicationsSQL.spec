# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['/Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts/linkedin_applications_gui_sql.py'],
    pathex=['/Users/grigorymordokhovich/Documents/Develop/LinkedIn/scripts'],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='LinkInJob',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='LinkInJob',
)
app = BUNDLE(
    coll,
    name='LinkInJob.app',
    icon='/Users/grigorymordokhovich/Documents/Develop/LinkedIn/assets/LinkedIn.icns',
    bundle_identifier='com.grigorym.LinkInJob',
)
