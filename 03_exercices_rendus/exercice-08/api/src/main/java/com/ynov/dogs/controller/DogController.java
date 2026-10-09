package com.ynov.dogs.controller;

import com.ynov.dogs.model.Dog;
import com.ynov.dogs.service.DogService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/dogs")
public class DogController {

    private final DogService dogService;

    public DogController(DogService dogService) {
        this.dogService = dogService;
    }

    @GetMapping
    public List<Dog> list() {
        return dogService.findAll();
    }

    @GetMapping("/{dogId}")
    public Dog get(@PathVariable Long dogId) {
        return dogService.findById(dogId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Dog create(@RequestBody Dog dog) {
        return dogService.create(dog);
    }

    @PutMapping("/{dogId}")
    public Dog update(@PathVariable Long dogId, @RequestBody Dog dog) {
        return dogService.update(dogId, dog);
    }

    @DeleteMapping("/{dogId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long dogId) {
        dogService.delete(dogId);
    }
}
