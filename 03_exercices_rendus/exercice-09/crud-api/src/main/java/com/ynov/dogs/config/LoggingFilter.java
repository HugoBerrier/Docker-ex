package com.ynov.dogs.config;

import com.ynov.dogs.client.LogsClient;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
public class LoggingFilter extends OncePerRequestFilter {

    private final LogsClient logsClient;

    public LoggingFilter(LogsClient logsClient) {
        this.logsClient = logsClient;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String path = request.getRequestURI();
        if (!path.startsWith("/api/v1/dogs")) {
            filterChain.doFilter(request, response);
            return;
        }

        try {
            filterChain.doFilter(request, response);
            int status = response.getStatus();
            String level = status >= 400 ? "ERR" : "INFO";
            String message = status >= 400
                    ? "HTTP " + status + " on " + request.getMethod() + " " + path
                    : "HTTP " + status + " OK";
            logsClient.send(message, request.getMethod(), path, level);
        } catch (Exception ex) {
            logsClient.send(ex.getMessage(), request.getMethod(), path, "ERR");
            throw ex;
        }
    }
}
