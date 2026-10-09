package com.ynov.logs.service;

import com.ynov.logs.model.LogEntry;
import com.ynov.logs.repository.LogRepository;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class LogService {

    private final LogRepository logRepository;

    public LogService(LogRepository logRepository) {
        this.logRepository = logRepository;
    }

    public List<LogEntry> findAll() {
        return logRepository.findAll();
    }

    public LogEntry create(LogEntry logEntry) {
        logEntry.setId(null);
        return logRepository.save(logEntry);
    }
}
