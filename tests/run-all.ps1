# Run:  powershell -ExecutionPolicy Bypass -File tests\run-all.ps1
# Needs: the dev server (npm.cmd run dev), the database container, and the
# seed data in its fresh state (tests\reset-db.ps1). Writes docs\test_results.md.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "helpers.ps1")

if ((Send "none" "GET" "/api/health" $null) -ne 200) {
  Write-Host "The app is not answering on $script:Base/api/health. Start the database container and run: npm.cmd run dev"
  exit 1
}
foreach ($u in "asha", "karthik", "sneha", "ravi") { Login $u }

# ---------------------------------------------------------------- communities
Section "Communities"
Check "List communities is public" "none" "GET" "/api/communities" $null 200
CheckTrue "5 communities are returned" ($script:Last.communities.Count -eq 5)
Check "mine=true needs a session" "none" "GET" "/api/communities?mine=true" $null 401
Check "mine=true for asha" "asha" "GET" "/api/communities?mine=true" $null 200
CheckTrue "asha is in communities 1, 2 and 3" ((($script:Last.communities | ForEach-Object { $_.communityId }) -join ",") -eq "1,2,3")
Check "Join community 4" "asha" "POST" "/api/communities/4/join" $null 201
Check "Joining twice is a conflict (primary key)" "asha" "POST" "/api/communities/4/join" $null 409
Check "Joining a missing community (foreign key)" "asha" "POST" "/api/communities/999/join" $null 404
Check "Joining needs a session" "none" "POST" "/api/communities/4/join" $null 401
Check "Leave community 4" "asha" "DELETE" "/api/communities/4/join" $null 200
Check "Leaving when not a member" "asha" "DELETE" "/api/communities/4/join" $null 404

# ----------------------------------------------------------------------- tags
Section "Tags"
Check "List tags with published-post counts" "none" "GET" "/api/tags" $null 200
Check "minPosts=0 includes unused tags" "none" "GET" "/api/tags?minPosts=0" $null 200
CheckTrue "Unused tag rust has 0 posts" ((($script:Last.tags | Where-Object { $_.tagName -eq "rust" }).postCount) -eq 0)
Check "Negative minPosts is rejected" "none" "GET" "/api/tags?minPosts=-1" $null 400

# ------------------------------------------------------------------- comments
Section "Comments"
Check "Read comments of published post 1" "none" "GET" "/api/posts/1/comments" $null 200
CheckTrue "Post 1 has 4 comments" ($script:Last.comments.Count -eq 4)
Check "Read comments of post 7" "none" "GET" "/api/posts/7/comments" $null 200
CheckTrue "Removed comment 8 shows [removed]" ((($script:Last.comments | Where-Object { $_.commentId -eq "8" }).content) -eq "[removed]")
CheckTrue "Reply 9 of the removed comment is kept" ($null -ne ($script:Last.comments | Where-Object { $_.commentId -eq "9" }))
Check "Draft post comments hidden from anonymous" "none" "GET" "/api/posts/10/comments" $null 404
Check "Draft post comments visible to its author" "asha" "GET" "/api/posts/10/comments" $null 200
Check "Removed post comments hidden" "none" "GET" "/api/posts/12/comments" $null 404

Check "Comment needs a session" "none" "POST" "/api/posts/1/comments" '{"content":"hi"}' 401
Check "Create a comment" "karthik" "POST" "/api/posts/1/comments" '{"content":"My comment","authorId":"1"}' 201
CheckTrue "authorId from the body is ignored (author is karthik, 4)" ($script:Last.comment.authorId -eq "4")
$myComment = $script:Last.comment.commentId
Check "Reply to that comment" "asha" "POST" "/api/posts/1/comments" ('{"content":"My reply","parentCommentId":"' + $myComment + '"}') 201
$myReply = $script:Last.comment.commentId
Check "Reply whose parent is on another post (C2)" "karthik" "POST" "/api/posts/1/comments" '{"content":"x","parentCommentId":"5"}' 400
Check "Reply to a missing parent" "karthik" "POST" "/api/posts/1/comments" '{"content":"x","parentCommentId":"99999"}' 400
Check "Blank content is rejected" "karthik" "POST" "/api/posts/1/comments" '{"content":"   "}' 400
Check "Invalid JSON is rejected" "karthik" "POST" "/api/posts/1/comments" 'not json' 400
Check "Comment on a draft post" "asha" "POST" "/api/posts/10/comments" '{"content":"draft"}' 404
Check "Comment on a removed post" "asha" "POST" "/api/posts/12/comments" '{"content":"removed post"}' 404

Check "Edit needs a session" "none" "PATCH" "/api/comments/$myComment" '{"content":"x"}' 401
Check "Edit someone else's comment" "asha" "PATCH" "/api/comments/$myComment" '{"content":"not mine"}' 403
Check "Edit own comment" "karthik" "PATCH" "/api/comments/$myComment" '{"content":"Edited"}' 200
Check "Edit a moderator-removed comment" "sneha" "PATCH" "/api/comments/8" '{"content":"edit removed"}' 409
Check "Delete a comment that has a reply (foreign key)" "karthik" "DELETE" "/api/comments/$myComment" $null 409
Check "Delete the reply" "asha" "DELETE" "/api/comments/$myReply" $null 200
Check "Delete the comment once it has no replies" "karthik" "DELETE" "/api/comments/$myComment" $null 200

Section "Moderation and comments"
Check "Admin removes comment 4" "ravi" "PATCH" "/api/admin/comments/4" '{"action":"remove"}' 200
Check "Comments of post 1 after removal" "none" "GET" "/api/posts/1/comments" $null 200
CheckTrue "Comment 4 now shows [removed]" ((($script:Last.comments | Where-Object { $_.commentId -eq "4" }).content) -eq "[removed]")
Check "Author cannot edit a removed comment" "sneha" "PATCH" "/api/comments/4" '{"content":"sneak edit"}' 409
Check "Admin restores comment 4" "ravi" "PATCH" "/api/admin/comments/4" '{"action":"restore"}' 200

# ------------------------------------------------------------------ reactions
# Post 9 has no seeded reactions, so these tests do not disturb the seed data.
[void](Send "asha" "DELETE" "/api/posts/9/reactions" $null)
[void](Send "karthik" "DELETE" "/api/posts/9/reactions" $null)
Section "Reactions"
Check "Reaction counts are public" "none" "GET" "/api/posts/9/reactions" $null 200
Check "Counts of a draft post" "none" "GET" "/api/posts/10/reactions" $null 404
Check "React needs a session" "none" "PUT" "/api/posts/9/reactions" '{"type":"like"}' 401
Check "First reaction is created" "asha" "PUT" "/api/posts/9/reactions" '{"type":"like"}' 201
Check "Reacting again replaces it (upsert)" "asha" "PUT" "/api/posts/9/reactions" '{"type":"love"}' 200
Check "Unknown type (CHECK, C3)" "asha" "PUT" "/api/posts/9/reactions" '{"type":"angry"}' 400
Check "Type longer than the column" "asha" "PUT" "/api/posts/9/reactions" '{"type":"thisiswaytoolong"}' 400
Check "Type that is not a string" "asha" "PUT" "/api/posts/9/reactions" '{"type":5}' 400
Check "Invalid JSON" "asha" "PUT" "/api/posts/9/reactions" 'not json' 400
Check "React to a draft post" "asha" "PUT" "/api/posts/10/reactions" '{"type":"like"}' 404
Check "React to a removed post" "asha" "PUT" "/api/posts/12/reactions" '{"type":"like"}' 404
Check "React to a missing post" "asha" "PUT" "/api/posts/999/reactions" '{"type":"like"}' 404
Check "Second user reacts" "karthik" "PUT" "/api/posts/9/reactions" '{"type":"insightful"}' 201
Check "Counts after two reactions" "asha" "GET" "/api/posts/9/reactions" $null 200
CheckTrue "Total is 2" ($script:Last.total -eq 2)
CheckTrue "asha's own reaction is love" ($script:Last.myReaction -eq "love")
Check "Remove own reaction" "asha" "DELETE" "/api/posts/9/reactions" $null 200
Check "Remove it again" "asha" "DELETE" "/api/posts/9/reactions" $null 404
Check "Cleanup: karthik removes his reaction" "karthik" "DELETE" "/api/posts/9/reactions" $null 200

# ------------------------------------------------------------------ bookmarks
[void](Send "asha" "DELETE" "/api/posts/9/bookmark" $null)
Section "Bookmarks"
Check "Bookmark needs a session" "none" "POST" "/api/posts/9/bookmark" $null 401
Check "Bookmark post 9" "asha" "POST" "/api/posts/9/bookmark" $null 201
Check "Bookmarking twice is a conflict (primary key)" "asha" "POST" "/api/posts/9/bookmark" $null 409
Check "Bookmark a draft post" "asha" "POST" "/api/posts/10/bookmark" $null 404
Check "Bookmark a removed post" "asha" "POST" "/api/posts/12/bookmark" $null 404
Check "Bookmark a missing post" "asha" "POST" "/api/posts/999/bookmark" $null 404
Check "Bookmark list needs a session" "none" "GET" "/api/bookmarks" $null 401
Check "Bookmark list" "asha" "GET" "/api/bookmarks" $null 200
CheckTrue "List contains post 9" ($null -ne ($script:Last.bookmarks | Where-Object { $_.postId -eq "9" }))
Check "Remove the bookmark" "asha" "DELETE" "/api/posts/9/bookmark" $null 200
Check "Remove it again" "asha" "DELETE" "/api/posts/9/bookmark" $null 404

# --------------------------------------------------------------------- follows
[void](Send "asha" "DELETE" "/api/users/1/follow" $null)
Section "Follows"
Check "Follow needs a session" "none" "POST" "/api/users/1/follow" $null 401
Check "Follow user 1" "asha" "POST" "/api/users/1/follow" $null 201
Check "Following twice is a conflict (primary key)" "asha" "POST" "/api/users/1/follow" $null 409
Check "Following yourself (CHECK, C1; asha is user 3)" "asha" "POST" "/api/users/3/follow" $null 400
Check "Following a missing user (foreign key)" "asha" "POST" "/api/users/999/follow" $null 404
Check "Non-numeric user id" "asha" "POST" "/api/users/abc/follow" $null 404
Check "Follow stats, anonymous" "none" "GET" "/api/users/1/follow" $null 200
CheckTrue "isFollowing is false for anonymous" ($script:Last.isFollowing -eq $false)
Check "Follow stats, asha" "asha" "GET" "/api/users/1/follow" $null 200
CheckTrue "isFollowing is true for asha" ($script:Last.isFollowing -eq $true)
CheckTrue "followerCount is at least 1" ($script:Last.followerCount -ge 1)
Check "Unfollow" "asha" "DELETE" "/api/users/1/follow" $null 200
Check "Unfollow again" "asha" "DELETE" "/api/users/1/follow" $null 404

# ------------------------------------------------------------ reading activity
Section "Reading activity"
Check "Logging a view needs a session" "none" "POST" "/api/posts/9/activity" $null 401
Check "Log a view" "asha" "POST" "/api/posts/9/activity" $null 201
Check "Log a second view (no unique key, a new row)" "asha" "POST" "/api/posts/9/activity" $null 201
Check "View of a draft post" "asha" "POST" "/api/posts/10/activity" $null 404
Check "View of a removed post" "asha" "POST" "/api/posts/12/activity" $null 404
Check "History needs a session" "none" "GET" "/api/activity" $null 401
Check "History" "asha" "GET" "/api/activity" $null 200
CheckTrue "Post 9 has at least 2 views (GROUP BY)" ((($script:Last.history | Where-Object { $_.postId -eq "9" }).views) -ge 2)

# ----------------------------------------------------------------- full-text search
Section "Full-text search"
$longQuery = "/api/search?q=" + ("a" * 501)
Check "q is required" "none" "GET" "/api/search" $null 400
Check "q must not be empty" "none" "GET" "/api/search?q=" $null 400
Check "q longer than 500 characters" "none" "GET" $longQuery $null 400
Check "community must be numeric" "none" "GET" "/api/search?q=index&community=abc" $null 400
Check "limit 0" "none" "GET" "/api/search?q=index&limit=0" $null 400
Check "limit 51" "none" "GET" "/api/search?q=index&limit=51" $null 400
Check "Negative offset" "none" "GET" "/api/search?q=index&offset=-1" $null 400
Check "Keyword search is public" "none" "GET" "/api/search?q=index" $null 200
CheckTrue "2 published posts match" ($script:Last.total -eq 2)
CheckTrue "Draft post 10 is hidden (C7)" (-not ($script:Last.posts.postId -contains "10"))
Check "Search while logged in" "asha" "GET" "/api/search?q=index" $null 200
Check "Phrase search" "none" "GET" "/api/search?q=%22b-tree%22" $null 200
CheckTrue "Phrase matches 1 post" ($script:Last.total -eq 1)
Check "Excluded word" "none" "GET" "/api/search?q=index+-transactions" $null 200
Check "Stop word only" "none" "GET" "/api/search?q=the" $null 200
CheckTrue "Stop word matches nothing" ($script:Last.total -eq 0)
Check "SQL-injection text is only text" "none" "GET" "/api/search?q=%27%3B+DROP+TABLE+users%3B--" $null 200
CheckTrue "users table still has 8 rows" ((Sql "SELECT count(*) FROM users;") -eq "8")
Check "Paging: first page of 1" "none" "GET" "/api/search?q=index&limit=1&offset=0" $null 200
$firstId = $script:Last.posts[0].postId
Check "Paging: second page of 1" "none" "GET" "/api/search?q=index&limit=1&offset=1" $null 200
CheckTrue "Second page is a different post" ($script:Last.posts[0].postId -ne $firstId)
Check "Offset beyond the last page" "none" "GET" "/api/search?q=index&offset=500" $null 200
CheckTrue "No posts beyond the last page" ($script:Last.posts.Count -eq 0)
Check "Filter by community 1" "none" "GET" "/api/search?q=index&community=1" $null 200
CheckTrue "Community 1 has 1 match" ($script:Last.total -eq 1)
Check "Filter by empty community 5" "none" "GET" "/api/search?q=index&community=5" $null 200
CheckTrue "Community 5 has 0 matches" ($script:Last.total -eq 0)
Check "Filter by tag" "none" "GET" "/api/search?q=index&tag=postgresql" $null 200
Check "Tag filter ignores case" "none" "GET" "/api/search?q=index&tag=PostgreSQL" $null 200
CheckTrue "Same total as the lowercase tag" ($script:Last.total -eq 2)
Check "Unused tag" "none" "GET" "/api/search?q=index&tag=rust" $null 200
CheckTrue "Unused tag matches 0" ($script:Last.total -eq 0)
Check "Search page loads" "none" "GET" "/search" $null 200

# ------------------------------------------------- constraints, straight to the database
Section "Database constraints (bypassing the API)"
CheckSql "C1: nobody follows themselves" "INSERT INTO follows (follower_id, followee_id) VALUES (3, 3);" "follows_not_self"
CheckSql "C3: reaction type is restricted" "INSERT INTO reactions (user_id, post_id, reaction_type) VALUES (3, 9, 'angry');" "violates check constraint"
CheckSql "C3: activity type is restricted" "INSERT INTO reading_activity (user_id, post_id, activity_type) VALUES (3, 9, 'click');" "violates check constraint"
CheckSql "C2: a reply must be on its parent's post" "INSERT INTO comments (post_id, author_id, content, parent_comment_id) VALUES (1, 3, 'x', 5);" "comments_reply_same_post"
CheckSql "C4: a published post needs published_at" "INSERT INTO posts (author_id, community_id, title, content, status) VALUES (3, 1, 't', 'c', 'published');" "posts_published_has_date"
CheckSql "C7: CHECK OPTION blocks a draft through the view" "INSERT INTO published_posts (author_id, community_id, title, content, status) VALUES (3, 1, 't', 'c', 'draft');" "check option"
CheckSql "Composite primary key: duplicate membership" "INSERT INTO community_members (user_id, community_id) VALUES (3, 1);" "community_members_pkey"

# --------------------------------------------------------------------- summary
$all = @($script:Results)
$failed = @($all | Where-Object { $_.Status -eq "FAIL" })
$passed = $all.Count - $failed.Count
""
"RESULT: $passed of $($all.Count) passed, $($failed.Count) failed"

$root = Split-Path $PSScriptRoot -Parent
$md = New-Object System.Collections.ArrayList
[void]$md.Add("# Test results")
[void]$md.Add("")
[void]$md.Add("Generated by ``tests/run-all.ps1`` on " + (Get-Date -Format "yyyy-MM-dd HH:mm") + ".")
[void]$md.Add("")
[void]$md.Add("**Summary: $passed of $($all.Count) test cases passed, $($failed.Count) failed.**")
[void]$md.Add("")
[void]$md.Add("Every test sends a real HTTP request to the running Next.js app, or an invalid SQL statement straight to PostgreSQL, and compares the outcome with the expected one. Status codes: 200 OK, 201 Created, 400 invalid input or constraint violation, 401 not logged in, 403 not allowed, 404 not found, 409 conflict.")
[void]$md.Add("")
[void]$md.Add("To reproduce: start the database and the app, run ``tests/reset-db.ps1`` for the seed data, then ``powershell -ExecutionPolicy Bypass -File tests\run-all.ps1``.")
foreach ($g in ($all | Group-Object Section)) {
  [void]$md.Add("")
  [void]$md.Add("### " + $g.Name)
  [void]$md.Add("")
  [void]$md.Add("| ID | Test | Call | Expected | Actual | Result |")
  [void]$md.Add("|---|---|---|---|---|---|")
  foreach ($r in $g.Group) {
    [void]$md.Add(('| {0} | {1} | `{2}` | {3} | {4} | {5} |' -f $r.Id, $r.Description, $r.Call, $r.Expected, $r.Actual, $r.Status))
  }
}
$out = Join-Path $root "docs\test_results.md"
[System.IO.File]::WriteAllLines($out, [string[]]$md, (New-Object System.Text.UTF8Encoding($false)))
"Results written to docs\test_results.md"
if ($failed.Count -gt 0) { exit 1 } else { exit 0 }