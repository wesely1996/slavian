-- Village layout: resource fields and center building slots, each with a
-- building and level. Filled in for older villages by upgradeLegacyVillages
-- on server start; `levels` stays as the derived highest level per building.
ALTER TABLE villages ADD COLUMN plots jsonb;
