# This script install all we need to set up a machine to deploy AA

#REMEMBER TO UPDATE USER/PASS
[CmdletBinding()]
param (
      [string] $user
    , [string] $pass
    , [string] $branch
)

$gitDirectory="C:\ansible\GIT" #set directory for cloning git repository
$aaWorspace="C:\AA_Auto_Build_Deploy" #set directory where put AA-ENV
$gitBranch=$branch #AA_ENV branch to use
$aaenv="https://" + $user +":" + $pass + "@github.com/Accela-Inc/AA-ENV.git"

#Check/set directory
If(!(test-path $gitDirectory))
{
    New-Item -ItemType Directory -Force -Path $gitDirectory
}
If(!(test-path $aaWorspace))
{
    New-Item -ItemType Directory -Force -Path $aaWorspace
}

#Cloning repository
echo "Cloning repository"
cd $gitDirectory
git clone $aaenv
cd AA-ENV
git checkout $gitBranch

#Copy AA-ENV into workspace directory
echo "Copy AA-ENV"
Copy-Item $gitDirectory/AA-ENV -Destination $aaWorspace/AA-ENV -Recurse
New-Item -ItemType Directory -Force -Path $aaWorspace/index

##########################
# install nvm + npm
##########################

echo "installing nvm"
choco install -y nvm
echo "update environment variables"
nvm install 8.11.1
refreshenv
echo "update nvm install/config"
refreshenv
nvm use 8.11.1
refreshenv
npm install -g bower
npm install -g grunt-cli
npm install -g karma

