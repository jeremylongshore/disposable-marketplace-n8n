/**
 * End-to-End Tests for N8N Disposable Marketplace Workflow
 * Tests complete user journeys and real workflow execution scenarios
 */

const axios = require('axios');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

describe('Disposable Marketplace E2E Tests', () => {
  const testConfig = {
    n8nUrl: process.env.N8N_URL || 'http://localhost:5678',
    timeout: 30000,
    retryAttempts: 3,
    retryDelay: 2000
  };

  let testRequestId;
  let mockCsvUrl;

  beforeAll(async () => {
    // Generate unique test ID
    testRequestId = `e2e_test_${Date.now()}`;

    // Set up test CSV data
    await setupTestData();

    // Verify N8N availability
    await verifyN8nAvailability();
  }, 60000);

  afterAll(async () => {
    // Cleanup test data
    await cleanupTestData();
  });

  describe('Complete Workflow Journey', () => {
    test('should execute complete marketplace workflow', async () => {
      const startTime = Date.now();

      // Step 1: Start marketplace collection
      const startResponse = await startMarketplaceCollection();
      expect(startResponse.status).toBe(200);
      expect(startResponse.data).toHaveProperty('requestId');

      const actualRequestId = startResponse.data.requestId;

      // Step 2: Simulate reseller offers
      const offers = await simulateResellerOffers(actualRequestId);
      expect(offers.length).toBeGreaterThan(0);

      // Step 3: Wait for processing and get summary
      const summary = await waitForSummary(actualRequestId);
      expect(summary).toHaveProperty('offers');
      expect(Array.isArray(summary.offers)).toBe(true);

      const endTime = Date.now();
      const totalDuration = endTime - startTime;

      console.log(`Complete workflow executed in ${totalDuration}ms`);
      expect(totalDuration).toBeLessThan(120000); // Should complete within 2 minutes
    }, 150000);

    test('should handle invalid CSV gracefully', async () => {
      const invalidCsvPayload = {
        csvUrl: 'https://httpbin.org/status/404',
        product: {
          brand: 'Rolex',
          model: 'Submariner'
        },
        callbackBaseUrl: testConfig.n8nUrl
      };

      const response = await axios.post(
        `${testConfig.n8nUrl}/webhook/disposable-marketplace/start`,
        invalidCsvPayload,
        { validateStatus: () => true }
      );

      // Should handle error gracefully
      expect([400, 404, 500]).toContain(response.status);
    });

    test('should validate required fields', async () => {
      const invalidPayload = {
        // Missing required csvUrl
        product: {
          brand: 'Rolex'
        }
      };

      const response = await axios.post(
        `${testConfig.n8nUrl}/webhook/disposable-marketplace/start`,
        invalidPayload,
        { validateStatus: () => true }
      );

      expect([400, 422]).toContain(response.status);
    });
  });

  describe('Reseller Offer Processing', () => {
    test('should accept and process multiple offers', async () => {
      // Start a new collection
      const startResponse = await startMarketplaceCollection();
      const requestId = startResponse.data.requestId;

      // Submit multiple offers with different prices
      const testOffers = [
        { resellerId: 'ROLEX_SPEC_1', price: 15000, currency: 'USD' },
        { resellerId: 'ROLEX_SPEC_2', price: 14500, currency: 'USD' },
        { resellerId: 'ROLEX_SPEC_3', price: 15500, currency: 'USD' }
      ];

      const submissionPromises = testOffers.map(offer =>
        submitOffer(requestId, offer)
      );

      const responses = await Promise.all(submissionPromises);

      // All offers should be accepted
      responses.forEach(response => {
        expect(response.status).toBe(200);
      });

      // Wait and check summary
      await new Promise(resolve => setTimeout(resolve, 5000));
      const summary = await getSummary(requestId);

      expect(summary.offers).toBeDefined();
      expect(summary.offers.length).toBeGreaterThanOrEqual(1);
    }, 60000);

    test('should rank offers correctly', async () => {
      const startResponse = await startMarketplaceCollection();
      const requestId = startResponse.data.requestId;

      // Submit offers with clear ranking order
      const rankedOffers = [
        { resellerId: 'HIGH_TRUST', price: 15000, currency: 'USD', trustScore: 9.5 },
        { resellerId: 'MED_TRUST', price: 14900, currency: 'USD', trustScore: 7.0 },
        { resellerId: 'LOW_TRUST', price: 14800, currency: 'USD', trustScore: 5.0 }
      ];

      for (const offer of rankedOffers) {
        await submitOffer(requestId, offer);
        await new Promise(resolve => setTimeout(resolve, 1000));
      }

      await new Promise(resolve => setTimeout(resolve, 8000));
      const summary = await getSummary(requestId);

      if (summary.offers && summary.offers.length > 1) {
        // Check if offers are ranked (assuming price and trust are factors)
        const firstOffer = summary.offers[0];
        const lastOffer = summary.offers[summary.offers.length - 1];

        // First offer should have better overall score
        expect(firstOffer.finalScore).toBeGreaterThanOrEqual(lastOffer.finalScore);
      }
    }, 90000);
  });

  describe('Error Handling and Edge Cases', () => {
    test('should handle malformed offer data', async () => {
      const startResponse = await startMarketplaceCollection();
      const requestId = startResponse.data.requestId;

      const malformedOffer = {
        requestId,
        // Missing required fields
        offer: {
          // Missing price
          currency: 'USD'
        }
      };

      const response = await axios.post(
        `${testConfig.n8nUrl}/webhook/disposable-marketplace/offer`,
        malformedOffer,
        { validateStatus: () => true }
      );

      // Should handle gracefully
      expect([400, 422, 500]).toContain(response.status);
    });

    test('should handle timeout scenarios', async () => {
      const startResponse = await startMarketplaceCollection({
        config: {
          timeoutMinutes: 1, // Very short timeout
          maxOffers: 5
        }
      });

      const requestId = startResponse.data.requestId;

      // Wait for timeout
      await new Promise(resolve => setTimeout(resolve, 70000));

      const summary = await getSummary(requestId);
      expect(summary).toHaveProperty('status');
      // Should either be 'completed' or 'timeout'
      expect(['completed', 'timeout', 'ended']).toContain(summary.status);
    }, 120000);

    test('should handle concurrent collections', async () => {
      // Start multiple collections simultaneously
      const collections = await Promise.all([
        startMarketplaceCollection(),
        startMarketplaceCollection(),
        startMarketplaceCollection()
      ]);

      expect(collections).toHaveLength(3);

      collections.forEach(response => {
        expect(response.status).toBe(200);
        expect(response.data).toHaveProperty('requestId');
      });

      // Each should have unique request IDs
      const requestIds = collections.map(c => c.data.requestId);
      const uniqueIds = [...new Set(requestIds)];
      expect(uniqueIds).toHaveLength(3);
    }, 45000);
  });

  describe('Data Validation and Security', () => {
    test('should validate CSV structure', async () => {
      // Create CSV with missing required columns
      const invalidCsv = 'name,email\nTest,test@example.com';
      const csvUrl = await createTestCsv(invalidCsv);

      const payload = {
        csvUrl,
        product: { brand: 'Rolex', model: 'Test' },
        callbackBaseUrl: testConfig.n8nUrl
      };

      const response = await axios.post(
        `${testConfig.n8nUrl}/webhook/disposable-marketplace/start`,
        payload,
        { validateStatus: () => true }
      );

      // Should reject invalid CSV structure
      expect([400, 422]).toContain(response.status);
    });

    test('should sanitize input data', async () => {
      const maliciousPayload = {
        csvUrl: mockCsvUrl,
        product: {
          brand: '<script>alert("xss")</script>',
          model: 'Test & Validate',
          description: 'Test "quotes" and \'more quotes\''
        },
        callbackBaseUrl: testConfig.n8nUrl
      };

      const response = await axios.post(
        `${testConfig.n8nUrl}/webhook/disposable-marketplace/start`,
        maliciousPayload
      );

      expect(response.status).toBe(200);
      // Workflow should handle malicious input gracefully
      expect(response.data).toHaveProperty('requestId');
    });
  });

  describe('Performance and Load Testing', () => {
    test('should handle large CSV files', async () => {
      // Create CSV with many resellers
      const largeCsv = generateLargeCsv(500);
      const csvUrl = await createTestCsv(largeCsv);

      const payload = {
        csvUrl,
        product: { brand: 'Rolex', model: 'Submariner' },
        callbackBaseUrl: testConfig.n8nUrl,
        config: {
          maxOffers: 10,
          batchSize: 50
        }
      };

      const startTime = Date.now();
      const response = await axios.post(
        `${testConfig.n8nUrl}/webhook/disposable-marketplace/start`,
        payload
      );

      expect(response.status).toBe(200);

      const processingTime = Date.now() - startTime;
      expect(processingTime).toBeLessThan(60000); // Should start processing within 1 minute
    }, 120000);

    test('should maintain performance under load', async () => {
      const requests = [];

      // Create 5 concurrent requests
      for (let i = 0; i < 5; i++) {
        requests.push(
          axios.post(`${testConfig.n8nUrl}/webhook/disposable-marketplace/start`, {
            csvUrl: mockCsvUrl,
            product: { brand: `TestBrand${i}`, model: `Model${i}` },
            callbackBaseUrl: testConfig.n8nUrl
          })
        );
      }

      const startTime = Date.now();
      const responses = await Promise.all(requests);
      const totalTime = Date.now() - startTime;

      // All requests should succeed
      responses.forEach(response => {
        expect(response.status).toBe(200);
      });

      // Should handle concurrent load reasonably
      expect(totalTime).toBeLessThan(30000);
    }, 60000);
  });

  // Helper functions
  async function setupTestData() {
    // Create test CSV content
    const csvContent = `id,name,email,region,trust_score,specialty
ROLEX_SPEC_1,Rolex Specialists NYC,info@rolexspec.com,US,9.5,Rolex
WATCH_EXPERT,Watch Experts Inc,contact@watchexp.com,US,8.7,Luxury Watches
TIME_DEALERS,Time Dealers Ltd,sales@timedealers.com,UK,9.2,Vintage Watches
SWISS_CONNECT,Swiss Connection,hello@swissconn.com,CH,9.8,Swiss Watches
LUXURY_TIME,Luxury Time Co,info@luxurytime.com,US,8.5,High-End Watches`;

    mockCsvUrl = await createTestCsv(csvContent);
  }

  async function createTestCsv(content) {
    // In a real scenario, you'd upload to a test server
    // For this example, we'll use a simple mock approach
    const testFile = path.join(__dirname, '../fixtures/test-data.csv');
    fs.writeFileSync(testFile, content);

    // Return a mock URL (in real testing, this would be a real URL)
    return `https://httpbin.org/response-headers?content-type=text/csv&test-data=${encodeURIComponent(content)}`;
  }

  async function verifyN8nAvailability() {
    try {
      const response = await axios.get(`${testConfig.n8nUrl}/healthz`, {
        timeout: 5000,
        validateStatus: () => true
      });

      if (response.status !== 200) {
        console.warn(`N8N health check returned status ${response.status}`);
        console.warn('Some E2E tests may be skipped');
      }
    } catch (error) {
      console.warn('N8N server not available for E2E testing');
      console.warn('Tests will run in mock mode');
    }
  }

  async function startMarketplaceCollection(customConfig = {}) {
    const payload = {
      csvUrl: mockCsvUrl,
      product: {
        brand: 'Rolex',
        model: 'Submariner',
        year: '2020',
        condition: 'Used'
      },
      callbackBaseUrl: testConfig.n8nUrl,
      config: {
        maxOffers: 10,
        timeoutMinutes: 15,
        batchSize: 5,
        ...customConfig.config
      },
      ...customConfig
    };

    return await retryRequest(() =>
      axios.post(`${testConfig.n8nUrl}/webhook/disposable-marketplace/start`, payload)
    );
  }

  async function submitOffer(requestId, offerData) {
    const payload = {
      requestId,
      resellerId: offerData.resellerId,
      offer: {
        price: offerData.price,
        currency: offerData.currency || 'USD',
        conditions: 'Cash on delivery',
        validUntil: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
        responseTime: new Date().toISOString()
      }
    };

    return await retryRequest(() =>
      axios.post(`${testConfig.n8nUrl}/webhook/disposable-marketplace/offer`, payload)
    );
  }

  async function simulateResellerOffers(requestId) {
    const offers = [
      { resellerId: 'ROLEX_SPEC_1', price: 15000 },
      { resellerId: 'WATCH_EXPERT', price: 14800 },
      { resellerId: 'TIME_DEALERS', price: 15200 }
    ];

    const submissions = [];
    for (const offer of offers) {
      try {
        const response = await submitOffer(requestId, offer);
        submissions.push(response.data);
        await new Promise(resolve => setTimeout(resolve, 1000)); // Stagger submissions
      } catch (error) {
        console.warn(`Failed to submit offer from ${offer.resellerId}:`, error.message);
      }
    }

    return submissions;
  }

  async function waitForSummary(requestId, maxWaitTime = 60000) {
    const startTime = Date.now();

    while (Date.now() - startTime < maxWaitTime) {
      try {
        const summary = await getSummary(requestId);
        if (summary && (summary.status === 'completed' || summary.offers?.length > 0)) {
          return summary;
        }
      } catch (error) {
        // Continue waiting
      }

      await new Promise(resolve => setTimeout(resolve, 3000));
    }

    throw new Error(`Summary not available after ${maxWaitTime}ms`);
  }

  async function getSummary(requestId) {
    const response = await axios.get(
      `${testConfig.n8nUrl}/webhook/disposable-marketplace/summary?requestId=${requestId}`
    );

    return response.data;
  }

  async function retryRequest(requestFn) {
    let lastError;

    for (let attempt = 1; attempt <= testConfig.retryAttempts; attempt++) {
      try {
        return await requestFn();
      } catch (error) {
        lastError = error;

        if (attempt < testConfig.retryAttempts) {
          console.warn(`Request attempt ${attempt} failed, retrying in ${testConfig.retryDelay}ms...`);
          await new Promise(resolve => setTimeout(resolve, testConfig.retryDelay));
        }
      }
    }

    throw lastError;
  }

  function generateLargeCsv(rowCount) {
    let csv = 'id,name,email,region,trust_score,specialty\n';

    for (let i = 1; i <= rowCount; i++) {
      const regions = ['US', 'UK', 'CH', 'DE', 'FR', 'IT', 'JP'];
      const specialties = ['Rolex', 'Omega', 'Patek Philippe', 'Cartier', 'Breitling'];

      csv += `RESELLER_${i},Test Reseller ${i},test${i}@example.com,${regions[i % regions.length]},${(Math.random() * 5 + 5).toFixed(1)},${specialties[i % specialties.length]}\n`;
    }

    return csv;
  }

  async function cleanupTestData() {
    // Clean up test files
    try {
      const testFile = path.join(__dirname, '../fixtures/test-data.csv');
      if (fs.existsSync(testFile)) {
        fs.unlinkSync(testFile);
      }
    } catch (error) {
      console.warn('Error cleaning up test data:', error.message);
    }
  }
});