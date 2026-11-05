# 운영 프로필 이미지 저장소

이 구성은 AWS 계정 `395931907754`의 프로필 이미지 버킷과 CloudFront를 관리합니다. 기존 운영 EC2 역할에는 프로필 경로의 쓰기 권한만 추가합니다. 배포 점검이 만든 이미지는 `profiles/.deployment-check/` 아래에 저장되며 1일 후 만료됩니다.

운영 계정의 AWS 세션을 선택한 뒤 이 디렉터리에서 계획을 검토합니다.

```sh
terraform init
terraform validate
terraform plan -out=profile-images.tfplan
terraform apply profile-images.tfplan
terraform output -json runtime_environment
```

출력의 세 이미지 설정을 SSM `/nearby/production/env` 아래에 반영합니다. 운영 서버의 현재 애플리케이션에 설정을 다시 로드한 뒤 Presigned PUT, 프로필 등록, 마이페이지 조회, CDN GET을 확인합니다. 새 CDN 주소는 새로 등록되는 이미지에 적용됩니다. 이전 URL이 저장된 프로필의 이미지를 옮길 때는 원본을 먼저 확인합니다.

장애 추적: [nearby-server#262](https://github.com/TEAM-Nearby/nearby-server/issues/262).
