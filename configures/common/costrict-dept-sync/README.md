# costrict-dept-sync

Department synchronization service packaged for CoStrict backend deployment.

    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
        reservations:
          cpus: "0.1"
          memory: 128M
