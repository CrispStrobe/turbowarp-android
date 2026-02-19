#!/usr/bin/env node
/**
 * Replaces scratch-gui/build/index.html with a redirect to editor.html so that
 * Capacitor (which always loads index.html from webDir on startup) opens the
 * full editor instead of the standalone player page.
 *
 * This script is run automatically as part of build:android / build:ios / build:all
 * in turbowarp-android/package.json. It does NOT affect the scratch-gui standalone
 * web build — that still produces a correct index.html (player page) when built
 * directly from scratch-gui/.
 */

const fs = require('fs');
const path = require('path');

const buildDir = path.resolve(__dirname, '../../scratch-gui/build');
const indexPath = path.join(buildDir, 'index.html');

if (!fs.existsSync(buildDir)) {
    console.error(`patch-index-for-capacitor: build dir not found: ${buildDir}`);
    process.exit(1);
}

const redirect = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="0;url=editor.html">
<script>location.replace('editor.html');</script>
</head>
</html>
`;

fs.writeFileSync(indexPath, redirect, 'utf8');
console.log('patch-index-for-capacitor: build/index.html → redirect to editor.html');
