<?php
/**
 * GitHub webhook to check Signed-Off-By in pull request commits.
 */

error_reporting(E_ALL);

define('PMAHOOKS', True);

require_once('./lib/github.php');

$contributing_url = 'https://github.com/phpmyadmin/phpmyadmin/blob/master/CONTRIBUTING.md';
$guidelines_url = 'http://wiki.phpmyadmin.net/pma/Developer_guidelines';

$message_sob = "This commit is missing Signed-Off-By line to indicate "
    . "that you agree with phpMyAdmin Developer's Certificate of Origin. "
    . "Please check [contributing documentation]("
    . $contributing_url
    . ") for more information.";

$message_tab = "This commit is using tab character for indentation instead "
    . "of spaces, what is mandated by phpMyAdmin. Please check our "
    . "[Developer guidelines]("
    . $guidelines_url
    . "#Indentation) for more information."
    . "\n\nOffending files: ";

/* Parse JSON */
$data = json_decode($_POST['payload'], true);

/* Check request data */
if (! isset($data['pull_request']) || ! isset($data['action'])) {
    die('No pull request data!');
}

/* We don't care about closed requests */
if ($data['action'] == 'closed') {
    die();
}

/* Parse repository name */
$repo_name = $data['pull_request']['head']['repo']['full_name'];

/* List commits in the pull request */
$commits = github_pull_commits($data['pull_request']['number']);

/* Process commits in the pull request */
foreach ($commits as $commit) {
    /* Fetch current comments */
    $current_comments = github_commit_comments($repo_name, $commit['sha'], $message_sob);
    $comments_text = '';
    foreach ($current_comments as $comment) {
        $comments_text .= $comment['body'];
    }

    /* Chek for missing SOB */
    if ( ! preg_match("@\nSigned-off-by:@i", $commit['commit']['message'])) {
        if (strpos($comments_text, $contributing_url) === false) {
            github_comment_commit($repo_name, $commit['sha'], $message_sob);
            echo 'Comment (SOB) on ' . $commit['sha'] . ":\n";
            echo $commit['commit']['message'];
            echo "\n";
        }
    }

    /* Check for tab in diff */
    $detail = github_commit_detail($commit['sha']);
    $files = array();
    foreach ($detail['files'] as $file) {
        if (strpos($file['patch'], "\t") !== false) {
            $files[] = $file['filename'];
        }
    }
    if (count($files) && strpos($comments_text, $guidelines_url) === false) {
        github_comment_commit($repo_name, $commit['sha'], $message_tab . implode(', ', $files));
        echo 'Comment (TAB) on ' . $commit['sha'] . ":\n";
        echo $commit['commit']['message'];
        echo "\n";
        break;
    }
}
