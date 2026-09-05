# Kanban Board

A simple offline-first iOS task board for organizing work into To Do, In Progress, and Done.

## What it does

- create, edit, and delete tasks
- move tasks between sections
- reorder tasks inside a section
- keep data saved across app relaunches
- work without needing the network

## Tech

The app uses Core Data as the main local store. The UI is built with SwiftUI and UIKit hosting, and the project is structured around a simple repository and view-model flow.

## Run it

Open the Xcode project and run the KanbanBoard scheme on an iOS simulator.

## Notes

This is a local-first app. Remote sync is not the primary source of truth and is not required for normal day-to-day use.