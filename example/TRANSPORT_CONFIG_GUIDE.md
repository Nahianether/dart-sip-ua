# SIP Transport Configuration Guide

This guide explains how to configure both WebSocket and TCP transport types in your SIP phone application.

## Transport Types Supported

### 1. WebSocket Transport (Recommended)
**Use when**: Your SIP server supports WebSocket connections
**Advantages**: 
- Works through firewalls and NAT
- Supports secure connections (WSS)
- Better compatibility with web environments

**Configuration**:
- **Transport Type**: `WebSocket`
- **Server URL Format**: `wss://server:port/path` or `ws://server:port/path`
- **Example**: `wss://sip.ibos.io:8089/ws`

### 2. TCP Transport
**Use when**: Your SIP server supports direct TCP connections
**Advantages**:
- Lower overhead than WebSocket
- Direct SIP protocol communication
- Traditional SIP setup

**Configuration**:
- **Transport Type**: `TCP`
- **Server URL Format**: `sip://server:port` or `server:port`
- **Default Port**: `5060` (unsecure) or `5061` (secure)
- **Example**: `sip.ibos.io:5060` or `sip://sip.ibos.io:5060`

## Configuration Examples

### WebSocket Configuration
```
Transport Type: WebSocket
Server URL: wss://sip.example.com:8089/ws
SIP URI: sip:username@sip.example.com
Username: your_username
Password: your_password
```

### TCP Configuration
```
Transport Type: TCP
Server URL: sip.example.com:5060
Port: 5060 (or leave empty for default)
SIP URI: sip:username@sip.example.com
Username: your_username
Password: your_password
```

## Troubleshooting

### WebSocket Issues
- **URL Format**: Must start with `ws://` or `wss://`
- **Path**: Include the WebSocket path (e.g., `/ws`)
- **SSL**: Use `wss://` for secure connections
- **Firewall**: WebSocket usually works through firewalls

### TCP Issues
- **Port**: Ensure the correct SIP port (usually 5060 or 5061)
- **Firewall**: TCP connections may be blocked by firewalls
- **NAT**: TCP may have issues behind NAT routers
- **Format**: Use `server:port` or `sip://server:port`

## Connection Logs

The app now provides detailed logging to help you troubleshoot:

### For WebSocket:
```
🚀 Transport configuration:
   Transport Type: WebSocket
   Server URL: wss://sip.ibos.io:8089/ws
📋 Transport Configuration Analysis:
   Selected: WebSocket
   Transport type matches URL format - optimal configuration
🔌 Configuring WebSocket transport...
📋 Final connection settings:
   Transport: WebSocket
   Host: sip.ibos.io
   WebSocket URL: wss://sip.ibos.io:8089/ws
```

### For TCP:
```
🚀 Transport configuration:
   Transport Type: TCP
   Server URL: sip.ibos.io:5060
📋 Transport Configuration Analysis:
   Selected: TCP
   Transport type matches URL format - optimal configuration
🔌 Configuring TCP transport...
📋 Final connection settings:
   Transport: TCP
   Host: sip.ibos.io
   Port: 5060
```

## Best Practices

1. **Start with WebSocket** - It's more likely to work through firewalls
2. **Use secure connections** when possible (`wss://` for WebSocket, port 5061 for TCP)
3. **Check server documentation** for supported transport types
4. **Test connectivity** using tools like telnet for TCP or browser for WebSocket
5. **Monitor logs** for specific error messages and troubleshooting guidance

## Common Configurations

### For Asterisk Server:
- **WebSocket**: `wss://your-server:8089/ws`
- **TCP**: `your-server:5060`

### For FreeSWITCH:
- **WebSocket**: `wss://your-server:7443`
- **TCP**: `your-server:5060`

### For Kamailio:
- **WebSocket**: `wss://your-server:443/ws`
- **TCP**: `your-server:5060`

Remember: The app will respect your transport choice and provide helpful guidance without auto-correcting your settings.