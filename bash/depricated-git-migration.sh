#!/bin/bash

## Cloning Bitbucket repo and changing to dev branch and removing .git folder


## Folder location

BitbucketFolder="/Folder/Location"
GitHubFolder="/Folder/Location"
GitHubTemplatesFolder="/Folder/Location"

cd TestRepo/
CheckDev=$(git branch --all | grep dev 2>&1)

if echo $CheckDev = 'dev' >/dev/null; then
   echo "dev branch exists"
   echo "Switching to dev branch ..."
   git checkout dev
else
   echo "dev branch does not exist"
   echo "Creating dev branch"	
   git branch dev
fi


# function GitHubTemplate(){

	

# }

function GitPushDev(){
	git add .
	git commit -m "Migrated Bitbucket dev to GitHub dev"
	git push origin dev
}


## Cloning Bitbucket repo

function Bitbucket(){
	cd "$BitbucketFolder"
	git clone git@RepoName
	cd $BitbucketRepo
	git checkout dev
	rm -rf .git
}

## Cloning GitHub repo

function GitHub(){
	cd "$GitHubFolder"
	git clone git@RepoName
	#GitClone=$(git clone git@RepoName/$GitHubRepo.git 2>&1)  #Halted for now
	cd $GitHubRepo
	git checkout -b dev
}


## Initiate the Main brach to an empty GitHub Repo
function GitHubMainInit(){
	echo "# $GitHubRepo" >> README.md
	git init
	git add README.md
	git commit -m "first commit"
	git branch -M main
	git remote add origin git@RepoName/$GitHubRepo.git
	git push -u origin main
}


# function CheckFolder(){
	

# }


## Asking user to input Bitbucket repo name
echo 'Please Provide The Bitbucket Repo Name'
read -p 'Bitbucket Repo: ' BitbucketRepo

## Asking user to input GitHub repo name
echo 'Please Provide The GitHub Repo Name'
read -p 'GitHub Repo: ' GitHubRepo


Bitbucket
GitHub

cp -arfp $BitbucketFolder/$BitbucketRepo/. $GitHubFolder/$GitHubRepo/



cd $GitHubFolder/$GitHubRepo
#GitPushDev


#echo $GitHubRepo



#echo $GitHubRepo
DUMP
=====================================
#!/bin/bash

## Cloning GitHub repo

RandomBla= $(cd "")

function GitHub(){
#	cd "/Folder/Location"
	cd "$GitHubFolder"
	#git clone git@RepoName/$GitHubRepo.git
	GitClone=$(git clone git@RepoName/$GitHubRepo.git 2>&1)
	#cd $GitHubRepo
	#git checkout dev
}

## Creates dev branch if it does not exists
function GitCheckBranchDev(){
	cd $GitHubRepo
	CheckDev=$(git branch --all | grep dev 2>&1)

	if echo $CheckDev = "dev" >/dev/null; then
		echo "dev branch exists"
		echo "Switching to dev branch ..."
		git checkout dev
	else
		echo "dev branch does not exist"
		echo "Creating dev branch"	
		git branch dev
	fi
}

## Creates stg branch if it does not exists
function GitCheckBranchStg(){
	CheckStg=$(git branch --all | grep stg 2>&1)

	if echo $CheckStg = 'stg' >/dev/null; then
		echo "stg branch exists"
		echo "Switching to stg branch ..."
		git checkout stg
	else
		echo "stg branch does not exist"
		echo "Creating stg branch"	
		git branch stg
	fi
}



## Asking user to input GitHub repo name
echo 'Please Provide The GitHub Repo Name'
read -p 'GitHub Repo: ' GitHubRepo


GitHub

if echo $GitClone | grep -q "You appear to have cloned an empty repository."; then
   echo "Creating main branch ..."
   GitHubMainInit
else
   echo "main brach already exist"
fi

GitCheckBranchDev


cd ..
cp -arfp YAML/* $GitHubRepo/


git add .
git commit -m "Commit to dev"
git commit origin dev


# git branch --show-current

#CheckDev=$(git branch --all | grep dev 2>&1)
#CheckStg=$(git branch --all | grep dev 2>&1)

# CheckDev=$(git branch --show-current 2>&1)
# CheckStg=$(git branch --show-current 2>&1)

## Dump
#git clone git@RepoName/TestRepo.git
#GitClone=$(git clone git@RepoName/TestRepo.git 2>&1)
#TestRepo.git

## git log 1 HEAD --pretty=format:%s

