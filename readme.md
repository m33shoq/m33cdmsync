Makes CDM layouts account wide, make sure to

- Saves layouts for the class on logout
- On login checks if layouts for the class changed and imports them if they are

Due to taint being a thing after import was performed it is necessary to do a /reload

Layout matching is performed by layout name so you will have to delete layouts that are

Initial setup may be tedious but works fine once you figure it out
