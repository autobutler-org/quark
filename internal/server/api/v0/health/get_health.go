package v0_health

import (
	"os"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// HealthJSON is the response for the health endpoint.
type HealthJSON struct {
	Healthy            bool      `json:"healthy"`
	Alerts             []string  `json:"alerts"`
	CPUPercent         float64   `json:"cpuPercent"`
	CPUCorePercents    []float64 `json:"cpuCorePercents"`
	CPUCoreCount       int       `json:"cpuCoreCount"`
	MemPercent         float64   `json:"memPercent"`
	MemUsedBytes       uint64    `json:"memUsedBytes"`
	MemTotalBytes      uint64    `json:"memTotalBytes"`
	DiskPercent        float64   `json:"diskPercent"`
	DiskUsedBytes      uint64    `json:"diskUsedBytes"`
	DiskTotalBytes     uint64    `json:"diskTotalBytes"`
	TemperatureCelsius float64   `json:"temperatureCelsius"`
	// Hostname is the OS hostname of the quark device.
	// Clients can use this to display the device's LAN name (e.g. quark.local).
	Hostname string `json:"hostname"`
}

// getHealth godoc
// @Summary Get system health status
// @Description Returns current hardware health: CPU, memory, disk usage and temperature. Sets healthy=false with alert messages when any metric exceeds its critical threshold.
// @Tags health
// @Produce json
// @Success 200 {object} HealthJSON
// @Security BearerAuth
// @Router /health [get]
func (r *router) getHealthRoute() *serverutil.Route {
	return serverutil.ApiRoute("GET", "/health", func(c *gin.Context) *serverutil.Response {
		status := r.collector.CurrentHealth()
		alerts := status.Alerts
		if alerts == nil {
			alerts = []string{}
		}
		corePercents := status.CPUCorePercents
		if corePercents == nil {
			corePercents = []float64{}
		}
		hostname, _ := os.Hostname()
		return serverutil.Ok().WithData(HealthJSON{
			Healthy:            status.Healthy,
			Alerts:             alerts,
			CPUPercent:         status.CPUPercent,
			CPUCorePercents:    corePercents,
			CPUCoreCount:       len(corePercents),
			MemPercent:         status.MemPercent,
			MemUsedBytes:       status.MemUsedBytes,
			MemTotalBytes:      status.MemTotalBytes,
			DiskPercent:        status.DiskPercent,
			DiskUsedBytes:      status.DiskUsedBytes,
			DiskTotalBytes:     status.DiskTotalBytes,
			TemperatureCelsius: status.TemperatureCelsius,
			Hostname:           hostname,
		})
	})
}
