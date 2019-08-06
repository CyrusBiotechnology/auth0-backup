# Auth0 Backup

[![Build Status](https://travis-ci.org/CyrusBiotechnology/auth0-backup.svg?branch=master)](https://travis-ci.org/CyrusBiotechnology/auth0-backup)

A short and sweet Auth0 tenant backup script, docker container and example k8s
configuration.

# Work in Progress

This repo is being edited so that instead of uploading to GCS, it commits to the `auth0-source` rc branch.

The cronjob command will also need to be edited. It will simply call this script.
