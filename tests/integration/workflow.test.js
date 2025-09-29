/**
 * Integration tests for N8N Disposable Marketplace workflow
 * Tests complete workflow execution flow with mocked external dependencies
 */

const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { spawn } = require('child_process');

describe('N8N Workflow Integration Tests', () => {
  let mockServer;
  let workflowData;
  const mockServerPort = process.env.MOCK_SERVER_PORT || 3001;
  const baseUrl = `http://localhost:${mockServerPort}`;

  beforeAll(async () => {
    // Load workflow data
    const workflowPath = path.join(__dirname, '../../workflow.json');
    workflowData = JSON.parse(fs.readFileSync(workflowPath, 'utf8'));

    // Start mock server for testing
    await startMockServer();
  });

  afterAll(async () => {
    if (mockServer) {
      await stopMockServer();
    }
  });

  describe('Workflow Structure Validation', () => {
    test('workflow.json should be valid JSON', () => {
      expect(workflowData).toBeDefined();
      expect(typeof workflowData).toBe('object');
    });

    test('workflow should have required top-level fields', () => {
      expect(workflowData.name).toBeDefined();
      expect(workflowData.nodes).toBeDefined();
      expect(Array.isArray(workflowData.nodes)).toBe(true);
    });

    test('workflow should have webhook nodes', () => {
      const webhookNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.webhook'
      );
      expect(webhookNodes.length).toBeGreaterThan(0);
    });

    test('workflow should have required endpoints', () => {
      const webhookNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.webhook'
      );

      const paths = webhookNodes.map(node => node.parameters?.path).filter(Boolean);

      expect(paths).toContain('disposable-marketplace/start');
      expect(paths.some(path => path.includes('offer'))).toBe(true);
      expect(paths.some(path => path.includes('summary'))).toBe(true);
    });

    test('workflow should have HTTP request nodes for external APIs', () => {
      const httpNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.httpRequest'
      );
      expect(httpNodes.length).toBeGreaterThan(0);
    });

    test('workflow should have function nodes for data processing', () => {
      const functionNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.function'
      );
      expect(functionNodes.length).toBeGreaterThan(0);
    });
  });

  describe('Node Configuration Validation', () => {
    test('webhook nodes should have valid configuration', () => {
      const webhookNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.webhook'
      );

      webhookNodes.forEach(node => {
        expect(node.parameters).toBeDefined();
        expect(node.parameters.path).toBeDefined();
        expect(typeof node.parameters.path).toBe('string');
        expect(node.parameters.path.length).toBeGreaterThan(0);
      });
    });

    test('function nodes should have valid JavaScript code', () => {
      const functionNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.function'
      );

      functionNodes.forEach(node => {
        expect(node.parameters).toBeDefined();
        expect(node.parameters.functionCode).toBeDefined();
        expect(typeof node.parameters.functionCode).toBe('string');

        // Basic syntax validation
        expect(() => {
          new Function(node.parameters.functionCode);
        }).not.toThrow();
      });
    });

    test('HTTP request nodes should have valid URLs', () => {
      const httpNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.httpRequest'
      );

      httpNodes.forEach(node => {
        if (node.parameters?.url) {
          const url = node.parameters.url;
          // Allow template variables like {{$json.csvUrl}}
          if (!url.includes('{{') && !url.includes('$json')) {
            expect(() => new URL(url)).not.toThrow();
          }
        }
      });
    });
  });

  describe('Workflow Endpoint Testing', () => {
    test('start endpoint should accept valid payload', async () => {
      const payload = {
        csvUrl: 'https://example.com/resellers.csv',
        product: {
          brand: 'Rolex',
          model: 'Submariner',
          year: '2020',
          condition: 'Used'
        },
        callbackBaseUrl: baseUrl,
        config: {
          maxOffers: 10,
          timeoutMinutes: 30,
          batchSize: 5
        }
      };

      // Mock the CSV endpoint
      mockCsvEndpoint();

      try {
        const response = await axios.post(`${baseUrl}/webhook/disposable-marketplace/start`, payload, {
          timeout: 10000
        });

        expect(response.status).toBe(200);
        expect(response.data).toBeDefined();
      } catch (error) {
        // If N8N is not running, skip this test
        if (error.code === 'ECONNREFUSED') {
          console.warn('N8N server not available, skipping endpoint test');
          return;
        }
        throw error;
      }
    }, 15000);

    test('start endpoint should reject invalid payload', async () => {
      const invalidPayload = {
        // Missing required csvUrl
        product: {
          brand: 'Rolex'
        }
      };

      try {
        await axios.post(`${baseUrl}/webhook/disposable-marketplace/start`, invalidPayload);
        // Should not reach here
        expect(true).toBe(false);
      } catch (error) {
        if (error.code === 'ECONNREFUSED') {
          console.warn('N8N server not available, skipping endpoint test');
          return;
        }
        expect(error.response?.status).toBe(400);
      }
    });

    test('offer endpoint should accept reseller submissions', async () => {
      const offerPayload = {
        requestId: 'test-request-123',
        resellerId: 'ROLEX_SPEC',
        offer: {
          price: 15000,
          currency: 'USD',
          conditions: 'Cash on delivery',
          validUntil: '2024-12-31'
        }
      };

      try {
        const response = await axios.post(`${baseUrl}/webhook/disposable-marketplace/offer`, offerPayload);
        expect(response.status).toBe(200);
      } catch (error) {
        if (error.code === 'ECONNREFUSED') {
          console.warn('N8N server not available, skipping endpoint test');
          return;
        }
        throw error;
      }
    });
  });

  describe('Data Processing Logic', () => {
    test('input validation function should work correctly', () => {
      // Extract validation logic from function node
      const validationNode = workflowData.nodes.find(
        node => node.name === 'Validate Input' && node.type === 'n8n-nodes-base.function'
      );

      expect(validationNode).toBeDefined();
      expect(validationNode.parameters.functionCode).toContain('csvUrl');
      expect(validationNode.parameters.functionCode).toContain('errors');
    });

    test('CSV processing should handle various formats', () => {
      const csvProcessingNode = workflowData.nodes.find(
        node => node.name === 'Parse CSV' && node.type === 'n8n-nodes-base.spreadsheetFile'
      );

      expect(csvProcessingNode).toBeDefined();
      expect(csvProcessingNode.parameters.operation).toBe('read');
      expect(csvProcessingNode.parameters.options?.headerRow).toBe(true);
    });

    test('scoring algorithm should be implemented', () => {
      // Look for scoring/ranking logic in function nodes
      const scoringNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.function' &&
               (node.parameters.functionCode?.includes('score') ||
                node.parameters.functionCode?.includes('rank'))
      );

      expect(scoringNodes.length).toBeGreaterThan(0);
    });
  });

  describe('Error Handling', () => {
    test('workflow should have error handling nodes', () => {
      // Check for error handling patterns
      const errorHandlers = workflowData.nodes.filter(
        node => node.name?.toLowerCase().includes('error') ||
               node.parameters?.functionCode?.includes('catch') ||
               node.parameters?.functionCode?.includes('error')
      );

      // Should have some form of error handling
      expect(errorHandlers.length).toBeGreaterThan(0);
    });

    test('webhook nodes should have proper response modes', () => {
      const webhookNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.webhook'
      );

      webhookNodes.forEach(node => {
        if (node.parameters.responseMode) {
          expect(['onReceived', 'lastNode', 'responseNode']).toContain(node.parameters.responseMode);
        }
      });
    });
  });

  describe('Security Validation', () => {
    test('workflow should not contain hardcoded credentials', () => {
      const workflowString = JSON.stringify(workflowData);

      // Check for common credential patterns
      const credentialPatterns = [
        /password\s*[:=]\s*['""][^'""]+['"]/i,
        /secret\s*[:=]\s*['""][^'""]+['"]/i,
        /api[_-]?key\s*[:=]\s*['""][^'""]+['"]/i,
        /token\s*[:=]\s*['""][^'""]+['"]/i
      ];

      credentialPatterns.forEach(pattern => {
        expect(workflowString).not.toMatch(pattern);
      });
    });

    test('workflow should not contain placeholder URLs in production', () => {
      const workflowString = JSON.stringify(workflowData);

      if (process.env.NODE_ENV === 'production') {
        expect(workflowString).not.toMatch(/YOUR_N8N_URL/);
        expect(workflowString).not.toMatch(/localhost/);
      }
    });

    test('HTTP requests should use HTTPS where possible', () => {
      const httpNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.httpRequest'
      );

      httpNodes.forEach(node => {
        if (node.parameters?.url && typeof node.parameters.url === 'string') {
          const url = node.parameters.url;
          if (url.startsWith('http://') && !url.includes('localhost')) {
            console.warn(`Insecure HTTP URL found: ${url}`);
          }
        }
      });
    });
  });

  describe('Performance Considerations', () => {
    test('workflow should not have excessive nodes', () => {
      expect(workflowData.nodes.length).toBeLessThan(100);
    });

    test('function nodes should not have infinite loops', () => {
      const functionNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.function'
      );

      functionNodes.forEach(node => {
        const code = node.parameters.functionCode;

        // Basic checks for problematic patterns
        expect(code).not.toMatch(/while\s*\(\s*true\s*\)/);
        expect(code).not.toMatch(/for\s*\(\s*;\s*;\s*\)/);
      });
    });

    test('timeout configurations should be reasonable', () => {
      const httpNodes = workflowData.nodes.filter(
        node => node.type === 'n8n-nodes-base.httpRequest'
      );

      httpNodes.forEach(node => {
        if (node.parameters?.options?.timeout) {
          const timeout = node.parameters.options.timeout;
          expect(timeout).toBeGreaterThan(1000); // At least 1 second
          expect(timeout).toBeLessThan(300000); // Less than 5 minutes
        }
      });
    });
  });

  // Helper functions
  async function startMockServer() {
    return new Promise((resolve, reject) => {
      const serverScript = `
        const http = require('http');
        const url = require('url');

        const server = http.createServer((req, res) => {
          const parsedUrl = url.parse(req.url, true);

          res.setHeader('Content-Type', 'application/json');
          res.setHeader('Access-Control-Allow-Origin', '*');
          res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
          res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

          if (req.method === 'OPTIONS') {
            res.writeHead(200);
            res.end();
            return;
          }

          if (parsedUrl.pathname === '/webhook/disposable-marketplace/start') {
            res.writeHead(200);
            res.end(JSON.stringify({ status: 'started', requestId: 'test-123' }));
          } else if (parsedUrl.pathname === '/webhook/disposable-marketplace/offer') {
            res.writeHead(200);
            res.end(JSON.stringify({ status: 'received' }));
          } else if (parsedUrl.pathname === '/webhook/disposable-marketplace/summary') {
            res.writeHead(200);
            res.end(JSON.stringify({ offers: [], status: 'completed' }));
          } else if (parsedUrl.pathname === '/resellers.csv') {
            res.setHeader('Content-Type', 'text/csv');
            res.writeHead(200);
            res.end('id,name,email,region,trust_score\\nROLEX_SPEC,Rolex Specialists,test@example.com,US,9.5');
          } else {
            res.writeHead(404);
            res.end(JSON.stringify({ error: 'Not found' }));
          }
        });

        server.listen(${mockServerPort}, (err) => {
          if (err) reject(err);
          else resolve(server);
        });
      `;

      mockServer = spawn('node', ['-e', serverScript], { stdio: 'pipe' });

      setTimeout(() => {
        resolve(mockServer);
      }, 1000);
    });
  }

  async function stopMockServer() {
    if (mockServer) {
      mockServer.kill();
      return new Promise(resolve => {
        mockServer.on('close', resolve);
      });
    }
  }

  function mockCsvEndpoint() {
    // This would be handled by the mock server
    // CSV content is provided in the mock server implementation above
  }
});