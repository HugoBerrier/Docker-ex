package com.ynov.dogs.repository;

import com.ynov.dogs.model.Dog;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DogRepository extends JpaRepository<Dog, Long> {
}
