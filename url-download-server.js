const express = require('express');
const { exec, spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');

const app = express();
const PORT = 3000;

// Middleware
app.use(express.json());
app.use(express.static('.'));

// Security: Only allow localhost connections
app.use((req, res, next) => {
    if (req.ip !== '127.0.0.1' && req.ip !== '::1' && req.ip !== '::ffff:127.0.0.1') {
        return res.status(403).json({ error: 'Access denied. Only localhost connections allowed.' });
    }
    next();
});

// Sanitize prefix input
function sanitizePrefix(prefix) {
    if (!prefix) return '';
    // Remove potentially dangerous characters, but allow spaces
    return prefix.replace(/[^a-zA-Z0-9_ -]/g, '_');
}

// Validate URL input
function isValidUrl(string) {
    try {
        new URL(string);
        return true;
    } catch (_) {
        return false;
    }
}

// Per-site configuration (sites/sites.json), re-read on every use so edits apply immediately
const SITES_FILE = path.join(__dirname, 'sites', 'sites.json');
const SITES_PLUGIN_DIR = path.join(__dirname, 'sites', 'plugins');

function loadSites() {
    try {
        const data = JSON.parse(fs.readFileSync(SITES_FILE, 'utf8'));
        return Array.isArray(data.sites) ? data.sites : [];
    } catch (error) {
        console.error('Error reading sites.json:', error.message);
        return [];
    }
}

function matchSite(url) {
    let hostname;
    try {
        hostname = new URL(url).hostname.toLowerCase();
    } catch (_) {
        return null;
    }
    return loadSites().find(site => (site.match || []).some(pattern => {
        const domain = String(pattern).toLowerCase();
        return hostname === domain || hostname.endsWith('.' + domain);
    })) || null;
}

// Build yt-dlp command arguments
function buildYtDlpArgs(url, prefix, destination, site) {
    // Sanitize prefix
    const sanitizedPrefix = sanitizePrefix(prefix);

    // Determine destination path
    let destinationPath;
    if (destination && typeof destination === 'string' && destination.trim()) {
        // Use provided destination, expand ~ if present
        destinationPath = destination.trim().replace(/^~/, os.homedir());
        // Ensure it's an absolute path
        if (!path.isAbsolute(destinationPath)) {
            destinationPath = path.resolve(destinationPath);
        }
    } else {
        // Default to Downloads folder
        destinationPath = path.join(os.homedir(), 'Downloads');
    }

    // Ensure destination directory exists
    try {
        if (!fs.existsSync(destinationPath)) {
            fs.mkdirSync(destinationPath, { recursive: true });
        }
    } catch (error) {
        console.error('Error creating destination directory:', error);
        // Fall back to Downloads folder
        destinationPath = path.join(os.homedir(), 'Downloads');
        if (!fs.existsSync(destinationPath)) {
            fs.mkdirSync(destinationPath, { recursive: true });
        }
    }

    // Build output filename with conditional prefix
    const outputTemplate = sanitizedPrefix ?
        `${destinationPath}/${sanitizedPrefix}-%(title)s.%(ext)s` :
        `${destinationPath}/%(title)s.%(ext)s`;

    // Build yt-dlp command arguments
    const siteArgs = site && Array.isArray(site.ytDlpArgs) ? site.ytDlpArgs.map(String) : [];
    const pluginArgs = fs.existsSync(SITES_PLUGIN_DIR) ? ['--plugin-dirs', SITES_PLUGIN_DIR] : [];

    return [
        ...pluginArgs,
        ...siteArgs,
        url,
        // '-f', 'best[height<=1080]/best',
        // '--impersonate', 'chrome:macos-14',
        '-o', outputTemplate
    ];
}

// SSE Download endpoint (streams yt-dlp output with progress)
app.get('/download-stream', (req, res) => {
    const { url, prefix, destination } = req.query;
    
    // Validate inputs
    if (!url || typeof url !== 'string') {
        res.write(`data: ${JSON.stringify({ type: 'error', message: 'URL is required' })}\n\n`);
        res.end();
        return;
    }
    
    if (!isValidUrl(url)) {
        res.write(`data: ${JSON.stringify({ type: 'error', message: 'Invalid URL format' })}\n\n`);
        res.end();
        return;
    }
    
    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    
    const site = matchSite(url);
    if (site) {
        res.write(`data: ${JSON.stringify({ type: 'site', id: site.id, name: site.name })}\n\n`);
    }
    
    const args = buildYtDlpArgs(url, prefix, destination, site);
    console.log(`Executing: yt-dlp ${args.join(' ')}`);
    
    // Use spawn to run yt-dlp
    const ytdlp = spawn('yt-dlp', args);
    
    let errorOutput = '';
    
    // Stream stdout to client
    ytdlp.stdout.on('data', (data) => {
        const text = data.toString();
        errorOutput += text; // Collect output for error display
        const lines = text.replace(/\r/g, '\n').split('\n');
        lines.forEach(line => {
            if (line.trim()) {
                res.write(`data: ${JSON.stringify({ type: 'output', line: line })}\n\n`);
            }
        });
    });
    
    // Stream stderr to client (yt-dlp outputs progress here)
    ytdlp.stderr.on('data', (data) => {
        const text = data.toString();
        errorOutput += text; // Collect stderr for error display
        const lines = text.replace(/\r/g, '\n').split('\n');
        lines.forEach(line => {
            if (line.trim()) {
                res.write(`data: ${JSON.stringify({ type: 'output', line: line })}\n\n`);
            }
        });
    });
    
    // Handle process completion
    ytdlp.on('close', (code) => {
        if (code !== 0) {
            res.write(`data: ${JSON.stringify({ type: 'error', message: `Download failed`, output: errorOutput.trim() })}\n\n`);
        } else {
            res.write(`data: ${JSON.stringify({ type: 'done' })}\n\n`);
        }
        res.end();
    });
    
    // Handle process errors
    ytdlp.on('error', (error) => {
        res.write(`data: ${JSON.stringify({ type: 'error', message: error.message })}\n\n`);
        res.end();
    });
    
    // Handle client disconnect
    req.on('close', () => {
        ytdlp.kill();
        res.end();
    });
});

// Save queue endpoint
app.post('/save-queue', (req, res) => {
    try {
        const { queue } = req.body;
        
        if (!queue || !Array.isArray(queue)) {
            return res.status(400).json({ success: false, error: 'Invalid queue data' });
        }
        
        // Create queue data in simple text format: url|prefix|status (status only if paused)
        const queueData = queue.map(item => {
            const url = item.url || '';
            const prefix = item.prefix || '';
            const status = item.status === 'paused' ? '|paused' : '';
            return `${url}|${prefix}${status}`;
        }).join('\n');
        
        // Fixed location: user's home directory
        const queueFilePath = path.join(os.homedir(), 'download-queue.txt');
        
        try {
            fs.writeFileSync(queueFilePath, queueData, 'utf8');
            res.json({ success: true, message: 'Queue saved successfully', path: queueFilePath });
        } catch (error) {
            console.error('Error saving queue:', error);
            res.status(500).json({ success: false, error: 'Failed to save queue', details: error.message });
        }
    } catch (error) {
        console.error('Error in save-queue endpoint:', error);
        res.status(500).json({ success: false, error: 'Internal server error', details: error.message });
    }
});

// Load queue endpoint
app.get('/load-queue', (req, res) => {
    try {
        const queueFilePath = path.join(os.homedir(), 'download-queue.txt');
        
        try {
            if (!fs.existsSync(queueFilePath)) {
                return res.json({ success: true, queue: [] });
            }
            
            const fileContent = fs.readFileSync(queueFilePath, 'utf8');
            const lines = fileContent.split('\n').filter(line => line.trim());
            
            const queue = lines.map(line => {
                const parts = line.split('|');
                const url = parts[0] || '';
                const prefix = parts[1] || '';
                const status = parts[2] === 'paused' ? 'paused' : 'pending';
                return { url, prefix, status };
            });
            
            res.json({ success: true, queue });
        } catch (error) {
            console.error('Error loading queue:', error);
            res.status(500).json({ success: false, error: 'Failed to load queue', details: error.message });
        }
    } catch (error) {
        console.error('Error in load-queue endpoint:', error);
        res.status(500).json({ success: false, error: 'Internal server error', details: error.message });
    }
});

// Site configurations for the Sites panel (read-only), with plugin source inlined
app.get('/api/sites', (req, res) => {
    const sites = loadSites().map(site => {
        let pluginSource = null;
        if (site.plugin) {
            const pluginPath = path.resolve(SITES_PLUGIN_DIR, String(site.plugin));
            if (pluginPath.startsWith(SITES_PLUGIN_DIR + path.sep)) {
                try {
                    pluginSource = fs.readFileSync(pluginPath, 'utf8');
                } catch (_) {
                    pluginSource = null;
                }
            }
        }
        return { ...site, pluginSource };
    });
    res.json({ sites });
});

// Health check endpoint
app.get('/health', (req, res) => {
    // The app launcher matches on `app` to tell this server from others on the port
    res.json({ status: 'ok', app: 'url-downloader', timestamp: new Date().toISOString() });
});

// Check if yt-dlp is installed
app.get('/check-ytdlp', (req, res) => {
    exec('yt-dlp --version', (error, stdout, stderr) => {
        if (error) {
            res.json({
                installed: false,
                error: 'yt-dlp is not installed or not in PATH'
            });
        } else {
            res.json({
                installed: true,
                version: stdout.trim()
            });
        }
    });
});

// List directory contents for folder picker
app.get('/list-directory', (req, res) => {
    try {
        const { path: requestedPath } = req.query;

        // Validate and resolve the path
        let targetPath;
        if (!requestedPath || requestedPath === 'home') {
            targetPath = os.homedir();
        } else if (requestedPath === 'downloads') {
            targetPath = path.join(os.homedir(), 'Downloads');
        } else if (requestedPath === 'desktop') {
            targetPath = path.join(os.homedir(), 'Desktop');
        } else {
            // Resolve the path and ensure it's safe
            targetPath = path.resolve(requestedPath.replace(/^~/, os.homedir()));

            // Security: Allow access to home directory, root, and volumes
            const homeDir = os.homedir();
            const volumesDir = '/Volumes/';
            const isAllowedPath = targetPath.startsWith(homeDir) ||
                                 targetPath === '/' ||
                                 targetPath.startsWith(volumesDir);

            if (!isAllowedPath) {
                return res.status(403).json({ error: 'Access denied: Path outside allowed directories' });
            }
        }

        // Check if directory exists
        if (!fs.existsSync(targetPath)) {
            return res.status(404).json({ error: 'Directory not found' });
        }

        // Check if it's actually a directory
        const stats = fs.statSync(targetPath);
        if (!stats.isDirectory()) {
            return res.status(400).json({ error: 'Path is not a directory' });
        }

        // Read directory contents
        const items = fs.readdirSync(targetPath, { withFileTypes: true });

        // Filter and format items (only show directories)
        const contents = items
            .filter(item => {
                // Only show directories
                if (!item.isDirectory()) {
                    return false;
                }

                // Exclude system directories
                const systemDirs = ['.fseventsd', '.Spotlight-V100', '.TemporaryItems', '.Trashes', '.DocumentRevisions-V100', '.DS_Store'];
                if (systemDirs.includes(item.name) || item.name.startsWith('.')) {
                    return false;
                }

                return true;
            })
            .map(item => ({
                name: item.name,
                type: 'directory',
                path: path.join(targetPath, item.name),
                size: null
            }))
            // Sort alphabetically
            .sort((a, b) => a.name.localeCompare(b.name));

        // Get parent directory path for navigation
        const parentPath = path.dirname(targetPath);
        const volumesDir = '/Volumes';
        const canGoUp = parentPath !== targetPath && (
            parentPath.startsWith(os.homedir()) || 
            parentPath === '/' || 
            parentPath.startsWith(volumesDir) ||
            targetPath.startsWith(volumesDir)
        );

        res.json({
            currentPath: targetPath,
            parentPath: canGoUp ? parentPath : null,
            contents: contents,
            homePath: os.homedir()
        });

    } catch (error) {
        console.error('Error listing directory:', error);
        res.status(500).json({ error: 'Failed to list directory contents' });
    }
});

// List available volumes/drives
app.get('/list-volumes', (req, res) => {
    try {
        const volumesPath = '/Volumes';
        let volumes = [];

        // Check if /Volumes exists and read its contents
        if (fs.existsSync(volumesPath)) {
            const items = fs.readdirSync(volumesPath, { withFileTypes: true });

            // Filter for directories (mounted volumes) and exclude system items
            const volumeItems = items
                .filter(item => {
                    // Only directories (mounted volumes)
                    if (!item.isDirectory()) return false;

                    // Exclude common system directories and hidden volumes
                    const excludedNames = ['.Trashes', '.fseventsd', '.Spotlight-V100', '.TemporaryItems', '.timemachine', 'com.apple.TimeMachine.localsnapshots'];

                    if (excludedNames.includes(item.name) || item.name.startsWith('.')) return false;

                    // Check if it's actually a mounted volume by verifying it has contents
                    // and isn't empty or just contains system files
                    try {
                        const volumePath = path.join(volumesPath, item.name);
                        const contents = fs.readdirSync(volumePath);
                        // Filter out hidden files and check if there are actual user files
                        const userFiles = contents.filter(file => !file.startsWith('.'));
                        return userFiles.length > 0;
                    } catch (error) {
                        // If we can't read it, it's probably not a valid mounted volume
                        return false;
                    }
                })
                .map(item => ({
                    name: item.name,
                    path: path.join(volumesPath, item.name),
                    type: 'volume'
                }));

            volumes.push(...volumeItems);
        }

        // Add the main system drive (/) as "Macintosh HD"
        try {
            // Check if root directory is accessible and has user directories
            const rootContents = fs.readdirSync('/');
            const hasUserDirs = ['Users', 'Applications', 'System'].some(dir => rootContents.includes(dir));

            if (hasUserDirs) {
                volumes.unshift({
                    name: 'Macintosh HD',
                    path: '/',
                    type: 'volume'
                });
            }
        } catch (error) {
            // If we can't access root, don't add it
            console.log('Cannot access root directory for Macintosh HD');
        }

        // Sort volumes alphabetically, but keep Macintosh HD first
        volumes.sort((a, b) => {
            if (a.name === 'Macintosh HD') return -1;
            if (b.name === 'Macintosh HD') return 1;
            return a.name.localeCompare(b.name);
        });

        res.json({ volumes });

    } catch (error) {
        console.error('Error listing volumes:', error);
        res.status(500).json({ error: 'Failed to list volumes', details: error.message });
    }
});

// Error handling - prevent process from exiting on errors
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
    console.error(error.stack);
    // Don't exit - keep server running
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
    // Don't exit - keep server running
});

// Prevent process from exiting
process.stdin.resume();

// Start server
let server;
try {
    server = app.listen(PORT, '127.0.0.1', () => {
        console.log(`URL Downloader server running at http://127.0.0.1:${PORT}`);
        console.log('Open your browser and navigate to the URL above');
        console.log('Make sure yt-dlp is installed: brew install yt-dlp');
        // Flush stdout to ensure message is written
        if (process.stdout.write) {
            process.stdout.write('');
        }
    });
} catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
}

// Handle server errors
server.on('error', (error) => {
    console.error('Server error:', error);
    if (error.code === 'EADDRINUSE') {
        console.error(`Port ${PORT} is already in use`);
    }
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down server...');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});

process.on('SIGTERM', () => {
    console.log('\nReceived SIGTERM, shutting down server...');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});

// Keep process alive - prevent exit on stdin close
setInterval(() => {
    // Keep process alive
}, 10000);

// Log that server is staying alive
setTimeout(() => {
    console.log('Server still running...');
}, 5000);
