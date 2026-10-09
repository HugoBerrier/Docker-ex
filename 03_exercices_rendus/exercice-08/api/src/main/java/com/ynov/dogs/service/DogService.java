package com.ynov.dogs.service;

import com.ynov.dogs.model.Dog;
import com.ynov.dogs.repository.DogRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@Service
public class DogService {

    private final DogRepository dogRepository;

    public DogService(DogRepository dogRepository) {
        this.dogRepository = dogRepository;
    }

    public List<Dog> findAll() {
        return dogRepository.findAll();
    }

    public Dog findById(Long id) {
        return dogRepository.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Dog not found: " + id));
    }

    public Dog create(Dog dog) {
        dog.setId(null);
        return dogRepository.save(dog);
    }

    public Dog update(Long id, Dog updated) {
        Dog existing = findById(id);
        existing.setName(updated.getName());
        existing.setBirthDate(updated.getBirthDate());
        existing.setBreed(updated.getBreed());
        existing.setSterilized(updated.isSterilized());
        return dogRepository.save(existing);
    }

    public void delete(Long id) {
        if (!dogRepository.existsById(id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Dog not found: " + id);
        }
        dogRepository.deleteById(id);
    }
}
