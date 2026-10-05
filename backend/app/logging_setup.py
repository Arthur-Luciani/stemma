import logging.config

LOG_FORMAT = "%(asctime)s %(levelname)s %(name)s: %(message)s"


def configure_logging(level: str) -> None:
    """Configura o logging do processo (root + uvicorn) com timestamp e nível do `LOG_LEVEL`."""
    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {"default": {"format": LOG_FORMAT}},
            "handlers": {
                "console": {"class": "logging.StreamHandler", "formatter": "default"},
            },
            "root": {"level": level.upper(), "handlers": ["console"]},
            "loggers": {
                # Uvicorn passa a usar o mesmo formato (propaga para o root).
                "uvicorn": {"handlers": [], "propagate": True},
                "uvicorn.error": {"handlers": [], "propagate": True},
                "uvicorn.access": {"handlers": [], "propagate": True},
            },
        }
    )
