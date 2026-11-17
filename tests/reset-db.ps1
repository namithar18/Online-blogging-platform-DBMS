# Run:  powershell -ExecutionPolicy Bypass -File tests\reset-db.ps1
# Reloads every SQL file in load order. schema.sql DROPS all tables first, so
# all data in the database is replaced by the seed data.
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$files = "db\schema.sql", "db\seed.sql", "db\advanced\triggers.sql", "db\advanced\views.sql", "db\advanced\indexes.sql", "db\advanced\fulltext.sql", "db\seed_embeddings.sql", "db\advanced\vector_search.sql"
foreach ($f in $files) {
  $out = Get-Content -Raw -Encoding UTF8 $f | docker exec -i blogdb_nextjs psql -U postgres -d blog 2>&1 | Out-String
  $errors = @($out -split "`n" | Where-Object { $_ -match "^(psql.*)?ERROR" }).Count
  "{0,-34} lines starting with ERROR: {1}" -f $f, $errors
}
"seed.sql, triggers.sql and views.sql print deliberate ERROR lines (invalid-insert demos); the others should print 0."
docker exec blogdb_nextjs psql -U postgres -d blog -c "SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM posts) AS posts, (SELECT count(*) FROM published_posts) AS published, (SELECT count(*) FROM post_embeddings) AS embeddings;"
"Expected: users 8, posts 12, published 9, embeddings 12."