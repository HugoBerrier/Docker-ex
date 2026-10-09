package com.ynov.dogs.client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;

@Component
public class LogsClient {

    private static final Logger log = LoggerFactory.getLogger(LogsClient.class);

    private final RestTemplate restTemplate;
    private final String logsApiUrl;

    public LogsClient(RestTemplate restTemplate,
                      @Value("${logs.api.url}") String logsApiUrl) {
        this.restTemplate = restTemplate;
        this.logsApiUrl = logsApiUrl;
    }

    public void send(String message, String method, String path, String level) {
        String source = "[CrudAPI] " + method + " " + path;
        LogPayload payload = new LogPayload(message, source, Instant.now().toString(), level);
        try {
            restTemplate.postForEntity(logsApiUrl + "/api/v1/logs", payload, Void.class);
        } catch (Exception e) {
            log.warn("Unable to send log to Logs API: {}", e.getMessage());
        }
    }
}
