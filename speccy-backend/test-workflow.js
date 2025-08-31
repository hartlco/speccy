#!/usr/bin/env node

/**
 * Test script for Speccy Backend API workflow
 * Demonstrates the complete flow from authentication to TTS generation and file download
 */

const API_BASE = 'http://localhost:3000';

async function testWorkflow() {
    console.log('🧪 Testing Speccy Backend API Workflow\n');
    
    // Test 1: Health check
    console.log('1️⃣ Testing health endpoint...');
    try {
        const response = await fetch(`${API_BASE}/health`);
        const health = await response.json();
        console.log('✅ Health check:', health);
    } catch (error) {
        console.error('❌ Health check failed:', error.message);
        return;
    }
    
    // Test 2: Authentication with invalid token (should fail)
    console.log('\n2️⃣ Testing authentication with invalid token...');
    try {
        const response = await fetch(`${API_BASE}/auth/verify`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ openai_token: 'sk-invalid-token' })
        });
        const auth = await response.json();
        if (response.status === 401) {
            console.log('✅ Invalid token correctly rejected:', auth.message);
        } else {
            console.log('❌ Expected rejection but got:', auth);
        }
    } catch (error) {
        console.error('❌ Auth test failed:', error.message);
    }
    
    // Test 3: Try TTS generation without auth (should fail)
    console.log('\n3️⃣ Testing TTS generation without authentication...');
    try {
        const response = await fetch(`${API_BASE}/tts/generate`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                text: 'Hello world',
                voice: 'nova',
                model: 'tts-1',
                format: 'mp3',
                speed: 1.0,
                openai_token: 'sk-test'
            })
        });
        const tts = await response.json();
        if (response.status === 401) {
            console.log('✅ Unauthorized request correctly rejected:', tts.message);
        } else {
            console.log('❌ Expected rejection but got:', tts);
        }
    } catch (error) {
        console.error('❌ TTS test failed:', error.message);
    }
    
    console.log('\n📝 To test with a real OpenAI token:');
    console.log('1. Get an OpenAI API key from https://platform.openai.com/api-keys');
    console.log('2. Run: node test-workflow.js sk-your-real-token-here');
    console.log('\n✅ Basic API structure tests completed!');
}

async function testWithRealToken(token) {
    console.log('🔑 Testing with real OpenAI token...\n');
    
    // Test authentication
    console.log('1️⃣ Authenticating...');
    let sessionToken;
    try {
        const response = await fetch(`${API_BASE}/auth/verify`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ openai_token: token })
        });
        const auth = await response.json();
        if (response.status === 200) {
            sessionToken = auth.session_token;
            console.log('✅ Authentication successful! User ID:', auth.user_id);
        } else {
            console.log('❌ Authentication failed:', auth.message);
            return;
        }
    } catch (error) {
        console.error('❌ Authentication error:', error.message);
        return;
    }
    
    // Test TTS generation
    console.log('\n2️⃣ Generating TTS...');
    let fileId;
    try {
        const response = await fetch(`${API_BASE}/tts/generate`, {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${sessionToken}`
            },
            body: JSON.stringify({
                text: 'Hello from the Speccy backend service!',
                voice: 'nova',
                model: 'tts-1',
                format: 'mp3',
                speed: 1.0,
                openai_token: token
            })
        });
        const tts = await response.json();
        if (response.status === 200) {
            fileId = tts.file_id;
            console.log('✅ TTS generation initiated!');
            console.log('   File ID:', tts.file_id);
            console.log('   Status:', tts.status);
            console.log('   Content Hash:', tts.content_hash);
            console.log('   Expires:', tts.expires_at);
        } else {
            console.log('❌ TTS generation failed:', tts.message);
            return;
        }
    } catch (error) {
        console.error('❌ TTS generation error:', error.message);
        return;
    }
    
    // Test file download (if ready)
    console.log('\n3️⃣ Testing file download...');
    try {
        const response = await fetch(`${API_BASE}/files/${fileId}`, {
            headers: { 'Authorization': `Bearer ${sessionToken}` }
        });
        if (response.status === 200) {
            const contentType = response.headers.get('content-type');
            const contentLength = response.headers.get('content-length');
            console.log('✅ File download successful!');
            console.log('   Content-Type:', contentType);
            console.log('   Content-Length:', contentLength, 'bytes');
            // Don't actually download the content in the test
        } else {
            console.log('ℹ️ File not ready for download yet (status:', response.status + ')');
        }
    } catch (error) {
        console.error('❌ File download error:', error.message);
    }
    
    console.log('\n✅ Complete workflow test finished!');
}

// Main execution
const args = process.argv.slice(2);
if (args.length > 0 && args[0].startsWith('sk-')) {
    testWithRealToken(args[0]);
} else {
    testWorkflow();
}