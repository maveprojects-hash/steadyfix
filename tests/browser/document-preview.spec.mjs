import { test, expect } from '@playwright/test';
import fs from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const source = await fs.readFile(path.join(root, 'maintdesk_app.html'), 'utf8');

function makeHarness() {
  let html = source;
  html = html.replace(
    /<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase\/supabase-js@2\/dist\/umd\/supabase\.min\.js"><\/script>/,
    '<script>window.supabase={createClient:()=>({})};</script>',
  );
  html = html.replace('<script src="communication.js"></script>', '');
  html = html.replace('<script src="industry_workspaces.js"></script>', '');
  html = html.replace(
    /aiInit\(\);\s*boot\(\);\s*intro\(\);/,
    'window.__SF_TEST_API__={docHtml,ovl,shareHtml,setCompany(v){CS=v;CO=v.label||"STEADYFIX Browser QA";}};',
  );
  if (!html.includes('window.__SF_TEST_API__')) {
    throw new Error('Could not create document-renderer browser harness from maintdesk_app.html');
  }
  return html;
}

const harness = makeHarness();
const company = {
  label: 'STEADYFIX Browser QA',
  subtitle: 'Document rendering acceptance',
  address: '12 Main Road, Cape Town',
  phone: '+27 21 555 0100',
  email: 'billing@example.test',
  currency: 'ZAR',
  doc_color: '#1f5f8b',
  doc_layout: 'classic',
  tax_rate: 15,
  terms: 'Payment due within 30 days.',
};
const customer = {
  name: 'Browser Test Customer',
  contact_person: 'QA Contact',
  address: 'PO Box 123, Cape Town',
  physical_address: '45 Long Street, Cape Town',
  email: 'qa-customer@example.test',
  phone: '+27 21 555 0199',
};
const invoice = {
  kind: 'invoice',
  number: 'INV-BROWSER-001',
  reference: 'Browser acceptance fixture',
  issue_date: '2026-11-24',
  due_date: '2026-12-24',
  sales_rep: 'QA Runner',
  discount_pct: 0,
  paid_amount: 0,
  vat_rate: 15,
  customer_name: customer.name,
  lines: [
    { d: 'Preventive maintenance service and inspection', q: 2, p: 1250, x: 0 },
    { d: 'Replacement filters and consumables', q: 3, p: 85, x: 0 },
    { d: 'Detailed follow-up report with recommendations', q: 1, p: 450, x: 0 },
  ],
  notes: 'Generated in Chromium for the STEADYFIX document acceptance test.',
};
const quote = {
  ...invoice,
  kind: 'quote',
  number: 'QUO-BROWSER-001',
  due_date: '2026-12-08',
  notes: 'This quotation is valid for fourteen days.',
};

async function loadHarness(page, viewport) {
  await page.setViewportSize(viewport);
  await page.setContent(harness, { waitUntil: 'load' });
  await page.evaluate(companyData => window.__SF_TEST_API__.setCompany(companyData), company);
  await page.waitForFunction(() => !!window.__SF_TEST_API__?.docHtml);
}

async function previewMetrics(page, doc, layout) {
  await page.evaluate(({ docData, layoutName, customerData, color }) => {
    const html = window.__SF_TEST_API__.docHtml(docData, customerData, {
      layout: layoutName,
      color,
    });
    window.__SF_TEST_API__.ovl(html);
  }, { docData: doc, layoutName: layout, customerData: customer, color: company.doc_color });
  await page.locator('#pv .dx').waitFor();
  return page.evaluate(() => {
    const overlay = document.querySelector('#pv');
    const paper = overlay?.querySelector('.dx');
    const content = overlay?.querySelector('div[style*="overflow-x:auto"]');
    return {
      viewport: window.innerWidth,
      overlayWidth: overlay?.clientWidth || 0,
      overlayScrollWidth: overlay?.scrollWidth || 0,
      paperWidth: paper?.clientWidth || 0,
      paperScrollWidth: paper?.scrollWidth || 0,
      contentWidth: content?.clientWidth || 0,
      contentScrollWidth: content?.scrollWidth || 0,
      itemRows: Array.from(paper?.querySelectorAll('.dxt2 tr:not(:first-child)') || []).map(row => ({
        display: getComputedStyle(row).display,
        labels: Array.from(row.querySelectorAll('td')).map(cell => cell.dataset.label),
      })),
      text: paper?.innerText || '',
    };
  });
}

test('quote and invoice previews remain readable at phone and desktop widths in every layout', async ({ page }) => {
  await loadHarness(page, { width: 390, height: 844 });
  const layouts = ['classic', 'modern', 'minimal', 'bold'];

  for (const [kind, doc] of [['invoice', invoice], ['quote', quote]]) {
    for (const layout of layouts) {
      const mobile = await previewMetrics(page, doc, layout);
      expect(mobile.text).toContain(doc.number);
      expect(mobile.text).toContain(customer.name);
      expect(mobile.text).toContain(company.label);
      expect(mobile.paperWidth).toBeGreaterThan(300);
      expect(mobile.paperScrollWidth).toBeLessThanOrEqual(mobile.paperWidth + 2);
      expect(mobile.contentScrollWidth).toBeLessThanOrEqual(mobile.contentWidth + 2);
      expect(mobile.overlayScrollWidth).toBeLessThanOrEqual(mobile.viewport + 2);
      expect(mobile.itemRows).toHaveLength(doc.lines.length);
      expect(mobile.itemRows.every(row => row.display === 'grid')).toBeTruthy();
      expect(mobile.itemRows[0].labels).toContain('Quantity');

      if (kind === 'invoice' && layout === 'classic') {
        await fs.mkdir(path.join(root, 'test-results'), { recursive: true });
        await page.screenshot({
          path: path.join(root, 'test-results', 'invoice-preview-mobile.png'),
          fullPage: true,
        });
      }
    }
  }

  await page.setViewportSize({ width: 1365, height: 900 });
  const desktop = await previewMetrics(page, invoice, 'classic');
  expect(desktop.text).toContain('INV-BROWSER-001');
  expect(desktop.paperWidth).toBeGreaterThanOrEqual(780);
  expect(desktop.paperScrollWidth).toBeLessThanOrEqual(desktop.paperWidth + 2);
  await page.screenshot({
    path: path.join(root, 'test-results', 'invoice-preview-desktop.png'),
    fullPage: true,
  });
});

test('PDF download and native file-share handoff contain a rendered non-blank page', async ({ page }) => {
  await loadHarness(page, { width: 1280, height: 900 });
  await page.addScriptTag({ path: path.join(root, 'node_modules/html2pdf.js/dist/html2pdf.bundle.min.js') });
  await page.addScriptTag({ path: path.join(root, 'node_modules/pdfjs-dist/build/pdf.min.js') });
  const pdfWorkerSource = await fs.readFile(path.join(root, 'node_modules/pdfjs-dist/build/pdf.worker.min.js'), 'utf8');
  await page.evaluate(workerSource => {
    const workerBlob = new Blob([workerSource], { type: 'text/javascript' });
    window.pdfjsLib.GlobalWorkerOptions.workerSrc = URL.createObjectURL(workerBlob);
    Object.defineProperty(navigator, 'share', { configurable: true, value: undefined });
    Object.defineProperty(navigator, 'canShare', { configurable: true, value: undefined });
  }, pdfWorkerSource);
  await page.evaluate(() => { window.print = () => {}; });
  page.on('dialog', dialog => dialog.accept());

  const invoiceHtml = await page.evaluate(({ docData, customerData, color }) =>
    window.__SF_TEST_API__.docHtml(docData, customerData, { layout: 'classic', color }),
  { docData: invoice, customerData: customer, color: company.doc_color });

  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.evaluate(({ html, to }) => window.__SF_TEST_API__.shareHtml(
      html,
      'Invoice_INV-BROWSER-001',
      'Invoice INV-BROWSER-001',
      'Please find the invoice attached.',
      to,
    ), { html: invoiceHtml, to: customer.email }),
  ]);

  expect(download.suggestedFilename()).toBe('Invoice_INV-BROWSER-001.pdf');
  const downloadPath = await download.path();
  expect(downloadPath).toBeTruthy();
  const pdfBytes = await fs.readFile(downloadPath);
  expect(pdfBytes.subarray(0, 5).toString()).toBe('%PDF-');
  expect(pdfBytes.byteLength).toBeGreaterThan(1500);

  const rendered = await page.evaluate(async base64 => {
    const raw = atob(base64);
    const data = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) data[i] = raw.charCodeAt(i);
    const pdf = await window.pdfjsLib.getDocument({ data }).promise;
    const pageMetrics = [];
    for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber++) {
      const pdfPage = await pdf.getPage(pageNumber);
      const viewport = pdfPage.getViewport({ scale: 1 });
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width);
      canvas.height = Math.ceil(viewport.height);
      const context = canvas.getContext('2d', { willReadFrequently: true });
      await pdfPage.render({ canvasContext: context, viewport }).promise;
      const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
      let nonWhite = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] < 245 || pixels[i + 1] < 245 || pixels[i + 2] < 245) nonWhite++;
      }
      pageMetrics.push({ width: viewport.width, height: viewport.height, nonWhiteRatio: nonWhite / (canvas.width * canvas.height) });
    }
    return { pages: pdf.numPages, pageMetrics };
  }, pdfBytes.toString('base64'));

  expect(rendered.pages).toBeGreaterThanOrEqual(1);
  expect(rendered.pageMetrics.length).toBe(rendered.pages);
  for (const pageMetric of rendered.pageMetrics) {
    expect(pageMetric.width).toBeGreaterThan(500);
    expect(pageMetric.height).toBeGreaterThan(700);
    expect(pageMetric.nonWhiteRatio).toBeGreaterThan(0.01);
  }

  await page.evaluate(() => {
    window.__sfNativeShare = null;
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: async payload => {
        window.__sfNativeShare = {
          title: payload.title,
          text: payload.text,
          files: Array.from(payload.files || []).map(file => ({
            name: file.name,
            type: file.type,
            size: file.size,
          })),
        };
      },
    });
    Object.defineProperty(navigator, 'canShare', {
      configurable: true,
      value: payload => !!payload?.files?.length,
    });
  });

  const quoteHtml = await page.evaluate(({ docData, customerData, color }) =>
    window.__SF_TEST_API__.docHtml(docData, customerData, { layout: 'modern', color }),
  { docData: quote, customerData: customer, color: company.doc_color });

  await page.evaluate(({ html, to }) => window.__SF_TEST_API__.shareHtml(
    html,
    'Quote_QUO-BROWSER-001',
    'Quote QUO-BROWSER-001',
    'Please review this quotation.',
    to,
  ), { html: quoteHtml, to: customer.email });

  const shared = await page.evaluate(() => window.__sfNativeShare);
  expect(shared?.title).toBe('Quote QUO-BROWSER-001');
  expect(shared?.files).toHaveLength(1);
  expect(shared.files[0].name).toBe('Quote_QUO-BROWSER-001.pdf');
  expect(shared.files[0].type).toBe('application/pdf');
  expect(shared.files[0].size).toBeGreaterThan(1500);
});
