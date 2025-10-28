ui <- fixedPage(
  h3("Simple shinyglide app"),
  glide(
    screen(
                     h2("Karelin_Bay 2021-12-19"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2021-12-19.png")),
screen(
                     h2("Karelin_Bay 2021-12-29"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2021-12-29.png")),
screen(
                     h2("Karelin_Bay 2022-12-30"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2022-12-30.png")),
screen(
                     h2("Karelin_Bay 2023-01-09"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-01-09.png")),
screen(
                     h2("Karelin_Bay 2023-03-20"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-03-20.png")),
screen(
                     h2("Karelin_Bay 2023-03-24"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-03-24.png")),
screen(
                     h2("Karelin_Bay 2023-03-30"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-03-30.png")),
screen(
                     h2("Karelin_Bay 2023-04-13"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-04-13.png")),
screen(
                     h2("Karelin_Bay 2023-08-31"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-08-31.png")),
screen(
                     h2("Karelin_Bay 2023-09-26"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-09-26.png")),
screen(
                     h2("Karelin_Bay 2023-10-20"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-10-20.png")),
screen(
                     h2("Karelin_Bay 2023-12-19"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2023-12-19.png")),
screen(
                     h2("Karelin_Bay 2024-03-28"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-03-28.png")),
screen(
                     h2("Karelin_Bay 2024-04-13"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-04-13.png")),
screen(
                     h2("Karelin_Bay 2024-08-31"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-08-31.png")),
screen(
                     h2("Karelin_Bay 2024-09-04"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-09-04.png")),
screen(
                     h2("Karelin_Bay 2024-11-03"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-11-03.png")),
screen(
                     h2("Karelin_Bay 2024-12-09"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-12-09.png")),
screen(
                     h2("Karelin_Bay 2024-12-19"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-12-19.png")),
screen(
                     h2("Karelin_Bay 2024-12-23"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-12-23.png")),
screen(
                     h2("Karelin_Bay 2024-12-29"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2024-12-29.png")),
screen(
                     h2("Karelin_Bay 2025-02-17"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2025-02-17.png")),
screen(
                     h2("Karelin_Bay 2025-02-27"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2025-02-27.png")),
screen(
                     h2("Karelin_Bay 2025-04-02"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2025-04-02.png")),
screen(
                     h2("Karelin_Bay 2025-10-05"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2025-10-05.png")),
screen(
                     h2("Karelin_Bay 2025-10-15"),
                     img(src = "https://projects.pawsey.org.au/geotar0/mk/www/pngs/Karelin_Bay_2025-10-15.png"))
  )
)
server <- function(input, output, session) {
}

shinyApp(ui, server)

