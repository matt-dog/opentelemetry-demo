// The OpenTelemetry Browser SDK for the shop's pages, loaded by the shopper (shopper.yaml) with
// Playwright's add_init_script, so it starts before the page's own scripts. Only the
// event-based instrumentations: the shop's own tracer (src/frontend, classic opentelemetry-js)
// already records fetch spans, and two instrumentations on the same API record every call twice.
// Events go out as OTLP log records to the page's own /otlp-http route (frontend-proxy), which
// forwards to the DDOT daemon Collector, and on to Datadog.
import { startBrowserSdk } from '@opentelemetry/browser-sdk';
import {
  createDefaultSessionIdGenerator,
  createLocalStorageSessionStore,
  createSessionLogRecordProcessor,
  createSessionManager,
} from '@opentelemetry/browser-sdk/session';
import { ConsoleInstrumentation } from '@opentelemetry/browser-instrumentation/experimental/console';
import { ErrorsInstrumentation } from '@opentelemetry/browser-instrumentation/experimental/errors';
import { NavigationInstrumentation } from '@opentelemetry/browser-instrumentation/experimental/navigation';
import { NavigationTimingInstrumentation } from '@opentelemetry/browser-instrumentation/experimental/navigation-timing';
import { ResourceTimingInstrumentation } from '@opentelemetry/browser-instrumentation/experimental/resource-timing';
import { UserActionInstrumentation } from '@opentelemetry/browser-instrumentation/experimental/user-action';
import { WebVitalsInstrumentation } from '@opentelemetry/browser-instrumentation/experimental/web-vitals';

(async () => {
  // Playwright runs init scripts on about:blank too, which has no origin to export to.
  if (location.origin === 'null') return;
  const sessionManager = createSessionManager({
    sessionIdGenerator: createDefaultSessionIdGenerator(),
    sessionStore: createLocalStorageSessionStore(),
    maxDuration: 4 * 60 * 60,
    inactivityTimeout: 30 * 60,
  });
  await sessionManager.start();
  window.__otelBrowser = startBrowserSdk({
    serviceName: 'frontend-web',
    serviceVersion: '3.1.0',
    // The shop's own tracer owns the global providers and context manager.
    setGlobals: false,
    logs: {
      processors: [createSessionLogRecordProcessor(sessionManager)],
      exportConfig: { url: `${location.origin}/otlp-http/v1/logs` },
    },
    instrumentations: [
      new NavigationTimingInstrumentation(),
      new NavigationInstrumentation(),
      // Not the telemetry's own requests: this SDK's and the shop tracer's OTLP exports, and the
      // Datadog Browser SDK's intake while it still runs (SHOPPER_DATADOG_RUM). Each export would
      // otherwise record a resource_timing event that is itself exported.
      new ResourceTimingInstrumentation({ ignoreUrls: [/\/otlp-http\//, /^https:\/\/browser-intake-/] }),
      new UserActionInstrumentation(),
      new WebVitalsInstrumentation(),
      new ErrorsInstrumentation(),
      new ConsoleInstrumentation(),
    ],
  });
})().catch((e) => console.warn('otel-browser: not started', e));
