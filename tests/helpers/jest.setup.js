/**
 * Jest setup configuration for N8N workflow tests
 * Configures global test environment and utilities
 */

// Extend Jest timeout for integration tests
jest.setTimeout(30000);

// Mock console methods to reduce noise in tests
const originalConsole = global.console;
global.console = {
  ...originalConsole,
  log: jest.fn((...args) => {
    if (process.env.TEST_DEBUG === 'true') {
      originalConsole.log(...args);
    }
  }),
  warn: jest.fn((...args) => {
    if (process.env.TEST_DEBUG === 'true') {
      originalConsole.warn(...args);
    }
  }),
  error: originalConsole.error, // Always show errors
  info: jest.fn((...args) => {
    if (process.env.TEST_DEBUG === 'true') {
      originalConsole.info(...args);
    }
  })
};

// Global test utilities
global.testUtils = {
  // Wait for condition with timeout
  waitFor: async (condition, timeout = 10000, interval = 100) => {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      if (await condition()) {
        return true;
      }
      await new Promise(resolve => setTimeout(resolve, interval));
    }
    throw new Error(`Condition not met within ${timeout}ms`);
  },

  // Generate test data
  generateTestData: {
    csvReseller: (id = 'TEST_001') => ({
      id,
      name: `Test Reseller ${id}`,
      email: `${id.toLowerCase()}@example.com`,
      region: 'US',
      trust_score: (Math.random() * 5 + 5).toFixed(1),
      specialty: 'Luxury Watches'
    }),

    product: (overrides = {}) => ({
      brand: 'Rolex',
      model: 'Submariner',
      year: '2020',
      condition: 'Used',
      serial: 'ABC123456',
      ...overrides
    }),

    offer: (overrides = {}) => ({
      price: 15000,
      currency: 'USD',
      conditions: 'Cash on delivery',
      validUntil: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      responseTime: new Date().toISOString(),
      ...overrides
    })
  },

  // Create test CSV content
  createCsvContent: (resellers) => {
    const header = 'id,name,email,region,trust_score,specialty';
    const rows = resellers.map(r =>
      `${r.id},${r.name},${r.email},${r.region},${r.trust_score},${r.specialty || ''}`
    );
    return [header, ...rows].join('\n');
  },

  // Retry mechanism for flaky tests
  retry: async (fn, maxAttempts = 3, delay = 1000) => {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (error) {
        if (attempt === maxAttempts) {
          throw error;
        }
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
};

// Global test constants
global.testConstants = {
  TIMEOUTS: {
    SHORT: 5000,
    MEDIUM: 15000,
    LONG: 30000,
    E2E: 60000
  },

  ENDPOINTS: {
    START: '/webhook/disposable-marketplace/start',
    OFFER: '/webhook/disposable-marketplace/offer',
    SUMMARY: '/webhook/disposable-marketplace/summary'
  },

  MOCK_DATA: {
    VALID_CSV_URL: 'https://example.com/resellers.csv',
    INVALID_CSV_URL: 'https://example.com/not-found.csv',
    MALFORMED_CSV_URL: 'https://example.com/malformed.csv'
  }
};

// Setup and teardown helpers
beforeEach(() => {
  // Clear any previous test state
  jest.clearAllMocks();
});

afterEach(() => {
  // Cleanup after each test
  // Any cleanup logic here
});

// Handle unhandled promise rejections in tests
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  // Don't exit the process during tests
});

// Export test helpers for use in test files
module.exports = {
  testUtils: global.testUtils,
  testConstants: global.testConstants
};