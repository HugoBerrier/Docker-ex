package com.ynov.logs.controller;

import com.ynov.logs.model.LogEntry;
import com.ynov.logs.service.LogService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/logs")
public class LogController {

    private final LogService logService;

    public LogController(LogService logService) {
        this.logService = logService;
    }

    @GetMapping
    public List<LogEntry> list() {
        return logService.findAll();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public LogEntry create(@RequestBody LogEntry logEntry) {
        return logService.create(logEntry);
    }
}
