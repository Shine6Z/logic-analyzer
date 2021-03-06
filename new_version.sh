#!/bin/bash

#settings
debian_branch=debian
upstream_branch=upstream

new_version=$1

if [ -z "$new_version" ]; then
	echo "required argument version not given, usage:"
	echo "$0 <version>"
	exit
fi

#function exiting if branch is not clean
function check_branch_clean {
	if [ -n "$(git status -s)" ]; then
		echo "branch not clean, exit"
		exit
	fi
}

#function to change branch (with clean state and post state checking )
#second argument is for a version to rebase on
function goto_branch {
	branch_togo=$1
	check_branch_clean 
	current_branch=`git branch 2>&1 | grep '*'| sed 's/* //'`
	if [ "$current_branch" = "$branch_togo" ]; then
		echo "already on $branch_togo"
	else
		echo "checkout $branch_togo"
		git checkout $branch_togo
		check_branch_clean
	fi
	current_branch=`git branch 2>&1 | grep '*'| sed 's/* //'`
	if [ "$current_branch" != "$branch_togo" ]; then
		exit
	fi
	if [ -n "$2" ]; then
		tag=$2
		echo "reset $current_branch to $tag"
		git reset --hard $tag
		check_branch_clean
	fi
}

upstream_tag_version="v$new_version"

#--------------------------
#work in upstream branch
#--------------------------

#check if upstream tag version is set, if it is reset to that commit, if not we tag HEAD
if [ -z $(git tag -l $upstream_tag_version) ]; then
	goto_branch $upstream_branch
	echo "upstream branch not tagged"
	echo "tag $upstream_tag_version"
	git tag $upstream_tag_version
else
	echo "go to tag $upstream_tag_version"
	goto_branch $upstream_branch $upstream_tag_version

fi

#check if version is ok in configure.ac
configure_version=$(cat configure.ac |grep AC_INIT| sed 's/.*(\(.*\)).*/\1/'|awk -F, '{print $2}')
package_name=$(cat configure.ac |grep AC_INIT| sed 's/.*(\(.*\)).*/\1/'|awk -F, '{print $1}')
other_options=$(cat configure.ac |grep AC_INIT| sed 's/.*([^,]*,[^,]*\(.*\)).*/\1/')
if [ $configure_version = $new_version ]; then
	echo "configure.ac up to date"
else
	#if not but tag present we remove it (as we introduce change in upstream branch)
	if [ -n "$(git tag -l $upstream_tag_version)" ]; then
		echo "removing old tag"
		git tag -d $upstream_tag_version
	fi
	sed	-i 's/AC_INIT( *'"$package_name"' *, *'"$configure_version"' */AC_INIT('"$package_name"','"$new_version"'/' configure.ac
	echo "configure.ac updated"
	autoreconf -i
	git add configure.ac configure
	git commit -m "adjust version in configure.ac to $new_version"
fi

#--------------------------
#work in debian branch
#--------------------------

goto_branch $debian_branch

#check if rebase is needed
ncommit_upstream_ahead=$(git rev-list $debian_branch..$upstream_branch|wc -l)
ncommit_debian_ahead=$(git rev-list $upstream_branch..$debian_branch|wc -l)

if [ $ncommit_upstream_ahead = 0 ]; then
	echo "debian branch is up to date"
else
	echo "rebase debian branch on upstream branch"
	first_debian_commit=$(git rev-list upstream..debian | tail -n 1)
	git rebase --onto $upstream_tag_version $first_debian_commit^1 debian
fi

debian_version=$new_version-1

#check if debian/changelog is up to date, if not we update it with git dch
if [ -z "$(cat debian/changelog|grep "urgency="| grep "($debian_version)"| grep -v UNRELEASED)" ]; then
	echo "update debian/changelog"
	rm -f debian/changelog.dch
	git dch --release -N $debian_version --meta --commit --commit-msg="Update changelog for %(version)s release
		Git-Dch: Ignore"  $debian_branch -- debian/
else
	echo "debian/changelog is up to date"
fi

#run git buildpackage
if [ -n "$(git tag -l debian/$debian_version)" ]; then
	echo "remove existing tag debian/$debian_version"
	git tag -d debian/$debian_version
fi
echo "run git buildpackage"
git buildpackage --git-tag

echo "return to master branch"
check_branch_clean
git checkout master
