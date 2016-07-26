<?php
/**
 * GitHub operations layer.
 */

if (!defined('PMAHOOKS')) {
    die();
}

$GLOBALS['hook_secret'] = '';

require_once('./config.php');

$curl_base_opts = array(
    CURLOPT_USERPWD => GITHUB_USERNAME . ':' . GITHUB_PASSWORD,
    CURLOPT_USERAGENT => 'phpMyAdmin-bot',
    CURLOPT_RETURNTRANSFER => 1,
    CURLOPT_HTTPAUTH => CURLAUTH_BASIC,
    CURLOPT_HTTPHEADER => array('Content-Type: application/json'),
);

/**
 * Verifies signature from GitHub
 */
function github_verify_post()
{
    if (empty($GLOBALS['hook_secret'])) {
        return;
    }
    if (!isset($_SERVER['HTTP_X_HUB_SIGNATURE'])) {
        die("HTTP header 'X-Hub-Signature' is missing.");
    } elseif (!extension_loaded('hash')) {
        die("Missing 'hash' extension to check the secret code validity.");
    }

    list($algo, $hash) = explode('=', $_SERVER['HTTP_X_HUB_SIGNATURE'], 2) + array('', '');
    if (!in_array($algo, hash_algos(), TRUE)) {
        die("Hash algorithm '$algo' is not supported.");
    }
    $rawPost = file_get_contents('php://input');
    if ($hash !== hash_hmac($algo, $rawPost, $GLOBALS['hook_secret'])) {
        die('Hook secret does not match.');
    }
}

/**
 * Creates a GitHub release
 */
function github_make_release($tag, $version, $description)
{
    $ch = curl_init();

    //set the url, number of POST vars, POST data
    curl_setopt_array($ch, $GLOBALS['curl_base_opts']);
    curl_setopt($ch, CURLOPT_URL, 'https://api.github.com/repos/phpmyadmin/phpmyadmin/releases');
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(array('tag_name' => $tag, 'name' => $version, 'body' => $description)));

    //execute post
    $result = curl_exec($ch);

    //close connection
    curl_close($ch);

    return $result;
}

/**
 * Posts a comment on GitHub pull request
 */
function github_comment_pull($pullid, $comment)
{
    $ch = curl_init();

    //set the url, number of POST vars, POST data
    curl_setopt_array($ch, $GLOBALS['curl_base_opts']);
    curl_setopt($ch, CURLOPT_URL, 'https://api.github.com/repos/phpmyadmin/phpmyadmin/issues/' . $pullid . '/comments');
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(array('body' => $comment)));

    //execute post
    $result = curl_exec($ch);

    //close connection
    curl_close($ch);

    return json_decode($result, true);
}

/**
 * Posts a comment on GitHub commit request
 */
function github_comment_commit($repo, $sha, $comment)
{
    $ch = curl_init();

    //set the url, number of POST vars, POST data
    curl_setopt_array($ch, $GLOBALS['curl_base_opts']);
    curl_setopt($ch, CURLOPT_URL, 'https://api.github.com/repos/' . $repo . '/commits/' . $sha . '/comments');
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(array('body' => $comment)));

    //execute post
    $result = curl_exec($ch);

    //close connection
    curl_close($ch);

    return json_decode($result, true);
}

/**
 * Returns list of pull request commits.
 */
function github_pull_commits($pullid)
{
    $ch = curl_init();
    curl_setopt_array($ch, $GLOBALS['curl_base_opts']);
    curl_setopt($ch, CURLOPT_URL, 'https://api.github.com/repos/phpmyadmin/phpmyadmin/pulls/' . $pullid . '/commits');

    //execute post
    $result = curl_exec($ch);

    //close connection
    curl_close($ch);

    return json_decode($result, true);
}

/**
 * Returns diff of pull request commit detal.
 */
function github_commit_detail($commit)
{
    $ch = curl_init();
    curl_setopt_array($ch, $GLOBALS['curl_base_opts']);
    curl_setopt($ch, CURLOPT_URL, 'https://api.github.com/repos/phpmyadmin/phpmyadmin/commits/' . $commit);

    //execute post
    $result = curl_exec($ch);

    //close connection
    curl_close($ch);

    return json_decode($result, true);
}

/**
 * Returns diff of pull request commit detal.
 */
function github_commit_comments($repo, $sha)
{
    $ch = curl_init();
    curl_setopt_array($ch, $GLOBALS['curl_base_opts']);
    curl_setopt($ch, CURLOPT_URL, 'https://api.github.com/repos/' . $repo . '/commits/' . $sha . '/comments');

    //execute post
    $result = curl_exec($ch);

    //close connection
    curl_close($ch);

    return json_decode($result, true);
}

/**
 * Returns diff of pull request commits.
 */
function github_pull_diff($pullid)
{
    $ch = curl_init();
    curl_setopt_array($ch, $GLOBALS['curl_base_opts']);
    curl_setopt($ch, CURLOPT_URL, 'https://github.com/phpmyadmin/phpmyadmin/pull/' . $pullid . '.patch');

    //execute post
    $result = curl_exec($ch);

    //close connection
    curl_close($ch);

    return $result;
}

/**
 * Trigger website rendering.
 */
function trigger_website_render()
{
    $file = fopen(WEBSITE_HOOK, 'w');
    fclose($file);
}
