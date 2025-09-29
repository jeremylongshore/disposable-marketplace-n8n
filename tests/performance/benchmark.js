/**
 * Performance benchmarking tests for N8N workflow
 * Measures execution time, memory usage, and throughput
 */

const fs = require('fs');
const path = require('path');
const { spawn, exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

class PerformanceBenchmark {
  constructor() {
    this.results = {
      timestamp: new Date().toISOString(),
      system: this.getSystemInfo(),
      tests: []
    };
  }

  getSystemInfo() {
    const os = require('os');
    return {
      platform: os.platform(),
      arch: os.arch(),
      cpus: os.cpus().length,
      totalMemory: Math.round(os.totalmem() / 1024 / 1024) + 'MB',
      freeMemory: Math.round(os.freemem() / 1024 / 1024) + 'MB',
      nodeVersion: process.version
    };
  }

  async measureExecutionTime(name, fn) {
    const startTime = process.hrtime.bigint();
    const startMemory = process.memoryUsage();

    try {
      const result = await fn();
      const endTime = process.hrtime.bigint();
      const endMemory = process.memoryUsage();

      const executionTime = Number(endTime - startTime) / 1e6; // Convert to milliseconds
      const memoryDelta = {
        rss: endMemory.rss - startMemory.rss,
        heapUsed: endMemory.heapUsed - startMemory.heapUsed,
        heapTotal: endMemory.heapTotal - startMemory.heapTotal
      };

      this.results.tests.push({
        name,
        status: 'passed',
        executionTime,
        memoryDelta,
        result
      });

      return { executionTime, memoryDelta, result };
    } catch (error) {
      const endTime = process.hrtime.bigint();
      const executionTime = Number(endTime - startTime) / 1e6;

      this.results.tests.push({
        name,
        status: 'failed',
        executionTime,
        error: error.message
      });

      throw error;
    }
  }

  async runValidationScriptBenchmark() {
    console.log('📊 Running validation script performance tests...');

    const workflowPath = path.join(__dirname, '../../workflow.json');
    const validationScript = path.join(__dirname, '../../validate-workflow.sh');

    // Test 1: Basic validation (all checks)
    await this.measureExecutionTime('validation_script_full', async () => {
      const { stdout, stderr } = await execAsync(`bash "${validationScript}" --file "${workflowPath}" --timing`);
      return { stdout: stdout.length, stderr: stderr.length };
    });

    // Test 2: Security-only validation
    await this.measureExecutionTime('validation_script_security', async () => {
      const { stdout, stderr } = await execAsync(`bash "${validationScript}" --security-only --file "${workflowPath}"`);
      return { stdout: stdout.length, stderr: stderr.length };
    });

    // Test 3: Structure-only validation
    await this.measureExecutionTime('validation_script_structure', async () => {
      const { stdout, stderr } = await execAsync(`bash "${validationScript}" --structure-only --file "${workflowPath}"`);
      return { stdout: stdout.length, stderr: stderr.length };
    });

    // Test 4: Performance check only
    await this.measureExecutionTime('validation_script_performance', async () => {
      const { stdout, stderr } = await execAsync(`bash "${validationScript}" --performance-only --file "${workflowPath}"`);
      return { stdout: stdout.length, stderr: stderr.length };
    });

    // Test 5: Parallel vs Sequential comparison
    await this.measureExecutionTime('validation_script_parallel', async () => {
      const { stdout, stderr } = await execAsync(`bash "${validationScript}" --file "${workflowPath}"`);
      return { stdout: stdout.length, stderr: stderr.length };
    });

    await this.measureExecutionTime('validation_script_sequential', async () => {
      const { stdout, stderr } = await execAsync(`bash "${validationScript}" --no-parallel --file "${workflowPath}"`);
      return { stdout: stdout.length, stderr: stderr.length };
    });
  }

  async runFileProcessingBenchmark() {
    console.log('📁 Running file processing performance tests...');

    const workflowPath = path.join(__dirname, '../../workflow.json');

    // Test file size analysis
    await this.measureExecutionTime('file_size_analysis', async () => {
      const stats = fs.statSync(workflowPath);
      return {
        size: stats.size,
        created: stats.birthtime,
        modified: stats.mtime
      };
    });

    // Test JSON parsing performance
    await this.measureExecutionTime('json_parsing', async () => {
      const content = fs.readFileSync(workflowPath, 'utf8');
      const parsed = JSON.parse(content);
      return {
        contentLength: content.length,
        nodeCount: parsed.nodes?.length || 0,
        hasConnections: !!parsed.connections
      };
    });

    // Test multiple JSON operations
    await this.measureExecutionTime('json_multiple_operations', async () => {
      const iterations = 100;
      const results = [];

      for (let i = 0; i < iterations; i++) {
        const content = fs.readFileSync(workflowPath, 'utf8');
        const parsed = JSON.parse(content);
        results.push(parsed.nodes?.length || 0);
      }

      return {
        iterations,
        avgNodeCount: results.reduce((a, b) => a + b, 0) / results.length
      };
    });
  }

  async runLargeFileTests() {
    console.log('📈 Running large file processing tests...');

    // Create test files of various sizes
    const testSizes = [1000, 5000, 10000, 50000]; // Number of nodes

    for (const nodeCount of testSizes) {
      await this.measureExecutionTime(`large_workflow_${nodeCount}_nodes`, async () => {
        const largeWorkflow = this.generateLargeWorkflow(nodeCount);
        const testFile = path.join(__dirname, `../fixtures/large-workflow-${nodeCount}.json`);

        // Ensure fixtures directory exists
        const fixturesDir = path.dirname(testFile);
        if (!fs.existsSync(fixturesDir)) {
          fs.mkdirSync(fixturesDir, { recursive: true });
        }

        fs.writeFileSync(testFile, JSON.stringify(largeWorkflow, null, 2));

        // Test validation on large file
        try {
          const { stdout } = await execAsync(`bash "${path.join(__dirname, '../../validate-workflow.sh')}" --structure-only --file "${testFile}"`);
          return {
            fileSize: fs.statSync(testFile).size,
            nodeCount,
            validationOutput: stdout.length
          };
        } finally {
          // Clean up
          if (fs.existsSync(testFile)) {
            fs.unlinkSync(testFile);
          }
        }
      });
    }
  }

  generateLargeWorkflow(nodeCount) {
    const nodes = [];
    for (let i = 0; i < nodeCount; i++) {
      nodes.push({
        id: `node_${i}`,
        name: `Test Node ${i}`,
        type: 'n8n-nodes-base.function',
        parameters: {
          functionCode: `return [{json: {nodeId: '${i}', timestamp: new Date().toISOString(), data: 'test data for node ${i}'}}];`
        },
        position: [100 + (i % 10) * 200, 100 + Math.floor(i / 10) * 100],
        typeVersion: 2
      });
    }

    return {
      name: `Large Test Workflow (${nodeCount} nodes)`,
      nodes,
      connections: {},
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      settings: {},
      staticData: {}
    };
  }

  async runMemoryUsageTests() {
    console.log('🧠 Running memory usage tests...');

    const getMemoryUsage = () => {
      const usage = process.memoryUsage();
      return {
        rss: Math.round(usage.rss / 1024 / 1024 * 100) / 100, // MB
        heapUsed: Math.round(usage.heapUsed / 1024 / 1024 * 100) / 100,
        heapTotal: Math.round(usage.heapTotal / 1024 / 1024 * 100) / 100,
        external: Math.round(usage.external / 1024 / 1024 * 100) / 100
      };
    };

    // Test memory usage during multiple validations
    await this.measureExecutionTime('memory_stress_test', async () => {
      const initialMemory = getMemoryUsage();
      const validationScript = path.join(__dirname, '../../validate-workflow.sh');
      const workflowPath = path.join(__dirname, '../../workflow.json');

      // Run validation 20 times
      const memorySnapshots = [initialMemory];

      for (let i = 0; i < 20; i++) {
        await execAsync(`bash "${validationScript}" --structure-only --file "${workflowPath}"`);
        memorySnapshots.push(getMemoryUsage());
      }

      const finalMemory = getMemoryUsage();

      return {
        initialMemory,
        finalMemory,
        memoryGrowth: {
          rss: finalMemory.rss - initialMemory.rss,
          heapUsed: finalMemory.heapUsed - initialMemory.heapUsed
        },
        peakMemory: {
          rss: Math.max(...memorySnapshots.map(m => m.rss)),
          heapUsed: Math.max(...memorySnapshots.map(m => m.heapUsed))
        }
      };
    });
  }

  async runConcurrencyTests() {
    console.log('🔄 Running concurrency tests...');

    const validationScript = path.join(__dirname, '../../validate-workflow.sh');
    const workflowPath = path.join(__dirname, '../../workflow.json');

    // Test concurrent validations
    await this.measureExecutionTime('concurrent_validations', async () => {
      const concurrentCount = 5;
      const promises = [];

      for (let i = 0; i < concurrentCount; i++) {
        promises.push(
          execAsync(`bash "${validationScript}" --structure-only --file "${workflowPath}"`)
        );
      }

      const results = await Promise.all(promises);
      return {
        concurrentCount,
        allSuccessful: results.every(r => r.stdout.includes('VALIDATION SUMMARY')),
        avgOutputLength: results.reduce((sum, r) => sum + r.stdout.length, 0) / results.length
      };
    });
  }

  async runThroughputTests() {
    console.log('⚡ Running throughput tests...');

    // Test CSV processing throughput
    await this.measureExecutionTime('csv_processing_throughput', async () => {
      const csvSizes = [100, 500, 1000, 2000];
      const results = [];

      for (const size of csvSizes) {
        const csvContent = this.generateTestCSV(size);
        const csvFile = path.join(__dirname, `../fixtures/test-${size}.csv`);

        // Ensure fixtures directory exists
        const fixturesDir = path.dirname(csvFile);
        if (!fs.existsSync(fixturesDir)) {
          fs.mkdirSync(fixturesDir, { recursive: true });
        }

        fs.writeFileSync(csvFile, csvContent);

        const startTime = process.hrtime.bigint();

        // Simulate CSV processing
        const lines = csvContent.split('\n');
        const processed = lines.slice(1).map(line => {
          const [id, name, email, region, trustScore] = line.split(',');
          return { id, name, email, region, trustScore: parseFloat(trustScore) };
        }).filter(row => row.id);

        const endTime = process.hrtime.bigint();
        const processingTime = Number(endTime - startTime) / 1e6;

        results.push({
          size,
          processingTime,
          throughput: size / (processingTime / 1000), // rows per second
          processedRows: processed.length
        });

        // Clean up
        fs.unlinkSync(csvFile);
      }

      return { results };
    });
  }

  generateTestCSV(rowCount) {
    let csv = 'id,name,email,region,trust_score\n';
    for (let i = 1; i <= rowCount; i++) {
      csv += `RESELLER_${i},Test Reseller ${i},test${i}@example.com,US,${(Math.random() * 10).toFixed(1)}\n`;
    }
    return csv;
  }

  generateReport() {
    console.log('\n📋 Generating performance report...');

    const reportPath = path.join(__dirname, '../reports/performance-report.json');
    const reportDir = path.dirname(reportPath);

    // Ensure reports directory exists
    if (!fs.existsSync(reportDir)) {
      fs.mkdirSync(reportDir, { recursive: true });
    }

    // Add summary statistics
    this.results.summary = {
      totalTests: this.results.tests.length,
      passedTests: this.results.tests.filter(t => t.status === 'passed').length,
      failedTests: this.results.tests.filter(t => t.status === 'failed').length,
      avgExecutionTime: this.results.tests
        .filter(t => t.executionTime)
        .reduce((sum, t) => sum + t.executionTime, 0) / this.results.tests.length,
      slowestTest: this.results.tests
        .filter(t => t.executionTime)
        .sort((a, b) => b.executionTime - a.executionTime)[0]?.name
    };

    fs.writeFileSync(reportPath, JSON.stringify(this.results, null, 2));

    // Generate human-readable report
    const readableReportPath = path.join(reportDir, 'performance-report.md');
    const readableReport = this.generateReadableReport();
    fs.writeFileSync(readableReportPath, readableReport);

    console.log(`✅ Performance report saved to:`);
    console.log(`   JSON: ${reportPath}`);
    console.log(`   Markdown: ${readableReportPath}`);

    return this.results;
  }

  generateReadableReport() {
    const { summary, system, tests } = this.results;

    let report = `# Performance Benchmark Report\n\n`;
    report += `**Generated:** ${this.results.timestamp}\n\n`;

    report += `## System Information\n\n`;
    report += `- **Platform:** ${system.platform} (${system.arch})\n`;
    report += `- **CPUs:** ${system.cpus}\n`;
    report += `- **Memory:** ${system.totalMemory} total, ${system.freeMemory} free\n`;
    report += `- **Node.js:** ${system.nodeVersion}\n\n`;

    report += `## Summary\n\n`;
    report += `- **Total Tests:** ${summary.totalTests}\n`;
    report += `- **Passed:** ${summary.passedTests}\n`;
    report += `- **Failed:** ${summary.failedTests}\n`;
    report += `- **Average Execution Time:** ${summary.avgExecutionTime.toFixed(2)}ms\n`;
    report += `- **Slowest Test:** ${summary.slowestTest}\n\n`;

    report += `## Test Results\n\n`;
    report += `| Test Name | Status | Execution Time (ms) | Memory Impact |\n`;
    report += `|-----------|---------|-------------------|---------------|\n`;

    tests.forEach(test => {
      const memoryImpact = test.memoryDelta
        ? `${(test.memoryDelta.heapUsed / 1024 / 1024).toFixed(2)}MB`
        : 'N/A';

      report += `| ${test.name} | ${test.status} | ${test.executionTime?.toFixed(2) || 'N/A'} | ${memoryImpact} |\n`;
    });

    report += `\n## Performance Recommendations\n\n`;

    // Generate recommendations based on results
    const slowTests = tests.filter(t => t.executionTime > 5000);
    if (slowTests.length > 0) {
      report += `### Slow Tests (>5s)\n`;
      slowTests.forEach(test => {
        report += `- **${test.name}:** ${test.executionTime.toFixed(2)}ms - Consider optimization\n`;
      });
      report += `\n`;
    }

    const memoryIntensiveTests = tests.filter(t =>
      t.memoryDelta && t.memoryDelta.heapUsed > 50 * 1024 * 1024
    );
    if (memoryIntensiveTests.length > 0) {
      report += `### Memory Intensive Tests (>50MB)\n`;
      memoryIntensiveTests.forEach(test => {
        report += `- **${test.name}:** ${(test.memoryDelta.heapUsed / 1024 / 1024).toFixed(2)}MB\n`;
      });
      report += `\n`;
    }

    report += `---\n*Report generated by N8N Workflow Performance Benchmark*\n`;

    return report;
  }
}

// Main execution
async function main() {
  console.log('🚀 Starting N8N Workflow Performance Benchmark Suite\n');

  const benchmark = new PerformanceBenchmark();

  try {
    await benchmark.runValidationScriptBenchmark();
    await benchmark.runFileProcessingBenchmark();
    await benchmark.runLargeFileTests();
    await benchmark.runMemoryUsageTests();
    await benchmark.runConcurrencyTests();
    await benchmark.runThroughputTests();

    const results = benchmark.generateReport();

    console.log('\n🎉 Benchmark completed successfully!');
    console.log(`Total tests: ${results.summary.totalTests}`);
    console.log(`Passed: ${results.summary.passedTests}`);
    console.log(`Failed: ${results.summary.failedTests}`);
    console.log(`Average execution time: ${results.summary.avgExecutionTime.toFixed(2)}ms`);

    process.exit(0);
  } catch (error) {
    console.error('❌ Benchmark failed:', error.message);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = PerformanceBenchmark;